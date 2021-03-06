program convert_mpas

    use scan_input
    use mpas_mesh
    use target_mesh
    use remapper
    use file_output
    use field_list
    use timer

    implicit none

    ! Timers
    type (timer_type) :: total_timer, &
                         read_timer, &
                         remap_timer, &
                         write_timer

    integer :: stat
    character (len=1024) :: mesh_filename, data_filename
    type (mpas_mesh_type) :: source_mesh
    type (target_mesh_type) :: destination_mesh
    type (input_handle_type) :: handle
    type (input_field_type) :: field
    type (remap_info_type) :: remap_info
    type (output_handle_type) :: output_handle
    type (target_field_type) :: target_field
    type (field_list_type) :: include_field_list, exclude_field_list

    integer :: iRec
    integer :: nRecordsIn, nRecordsOut
    integer :: iFile
    integer :: fileArgStart, nArgs
    

    call timer_start(total_timer)

    if (command_argument_count() < 1) then
        write(0,*) ' '
        write(0,*) 'Usage: convert_mpas mesh-file [data-files]'
        write(0,*) ' '
        write(0,*) 'If only one file argument is given, both the MPAS mesh information and'
        write(0,*) 'the fields will be read from the specified file.'
        write(0,*) 'If two or more file arguments are given, the MPAS mesh information will'
        write(0,*) 'be read from the first file and fields to be remapped will be read from'
        write(0,*) 'the subsequent files.'
        write(0,*) 'All time records from input files will be processed and appended to'
        write(0,*) 'the output file.'
        stop 1
    end if

    nArgs = command_argument_count()

    call get_command_argument(1, mesh_filename)
    if (nArgs == 1) then
        fileArgStart = 1
    else 
        fileArgStart = 2
    end if

    write(0,*) 'Reading MPAS mesh information from file '''//trim(mesh_filename)//''''


    !
    ! Generate the target grid
    !
    if (target_mesh_setup(destination_mesh) /= 0) then
        write(0,*) 'Error: Problems setting up target mesh'
        stop 2
    end if

    !
    ! Get information defining the MPAS mesh
    !
    if (mpas_mesh_setup(mesh_filename, source_mesh) /= 0) then
        write(0,*) 'Error: Problems setting up MPAS mesh from file '//trim(mesh_filename)
        stat = target_mesh_free(destination_mesh)
        stop 3
    end if

    !
    ! Compute weights for mapping from MPAS mesh to target grid
    !
    write(0,*) ' '
    write(0,*) 'Computing remapping weights'
    call timer_start(remap_timer)
    if (remap_info_setup(source_mesh, destination_mesh, remap_info) /= 0) then
        write(0,*) 'Error: Problems setting up remapping'
        stat = mpas_mesh_free(source_mesh)
        stat = target_mesh_free(destination_mesh)
        stop 4
    end if
    call timer_stop(remap_timer)
    write(0,'(a,f10.6,a)') '    Time to compute remap weights: ', timer_time(remap_timer), ' s'

    !
    ! Open output file
    !
    if (file_output_open('latlon.nc', output_handle, mode=FILE_MODE_APPEND, nRecords=nRecordsOut) /= 0) then
        write(0,*) 'Error: Problems opening output file'
        stat = mpas_mesh_free(source_mesh)
        stat = target_mesh_free(destination_mesh)
        stat = remap_info_free(remap_info)
        stop 5
    end if

    if (nRecordsOut /= 0) then
        write(0,*) 'Existing output file has ', nRecordsOut, ' records'
    else
        write(0,*) 'Created a new output file'
    end if

    !
    ! Get list of fields to include or exclude from input file
    !
    stat = field_list_init(include_field_list, exclude_field_list)


    !
    ! Loop over input data files
    !
    do iFile=fileArgStart,nArgs
        call get_command_argument(iFile, data_filename)
        write(0,*) 'Remapping MPAS fields from file '''//trim(data_filename)//''''

        !
        ! Open input data file
        !
        if (scan_input_open(data_filename, handle, nRecords=nRecordsIn) /= 0) then
            write(0,*) 'Error: Problems opening input file '//trim(data_filename)
            write(0,*) '       This could result from an input file with no unlimited dimension.'
            stat = file_output_close(output_handle)
            stat = scan_input_close(handle)
            stat = mpas_mesh_free(source_mesh)
            stat = target_mesh_free(destination_mesh)
            stat = remap_info_free(remap_info)
            stop 6
        end if
    
        write(0,*) 'Input file has ', nRecordsIn, ' records'
    
! generally, we should make sure dimensions match in existing output files
! and in subsequent MPAS input files
    
        !
        ! Scan through input file, determine which fields will be remapped,
        ! and define those fields in the output file; this only needs to be done
        ! if there are no existing records in the output file (i.e., the output
        ! file is a new file)
        !
        write(0,*) ' '
        if (nRecordsOut == 0) then
            write(0,*) 'Defining fields in output file'

            ! Define 'lat' and 'lon' fields for target mesh
            stat = remap_get_target_latitudes(remap_info, target_field)
            stat = file_output_register_field(output_handle, target_field)
            stat = free_target_field(target_field)

            stat = remap_get_target_longitudes(remap_info, target_field)
            stat = file_output_register_field(output_handle, target_field)
            stat = free_target_field(target_field)

            do while (scan_input_next_field(handle, field) == 0) 
                if (can_remap_field(field) .and. &
                    should_remap_field(field, include_field_list, exclude_field_list)) then
                    stat = remap_field_dryrun(remap_info, field, target_field)
                    stat = file_output_register_field(output_handle, target_field)
                    if (stat /= 0) then
                        stat = free_target_field(target_field)
                        stat = scan_input_free_field(field)
                        stat = scan_input_close(handle)
                        stat = file_output_close(output_handle)
                        stat = mpas_mesh_free(source_mesh)
                        stat = target_mesh_free(destination_mesh)
                        stat = remap_info_free(remap_info)
                        stat = field_list_finalize(include_field_list, exclude_field_list)
                        stop 7
                    end if
        
                    stat = free_target_field(target_field)
                end if
                stat = scan_input_free_field(field)
            end do
        end if


        ! 
        ! Write 'lat' and 'lon' fields for target mesh
        ! 
        if (nRecordsOut == 0) then
            stat = remap_get_target_latitudes(remap_info, target_field)
            stat = file_output_write_field(output_handle, target_field, frame=0)
            stat = free_target_field(target_field)

            stat = remap_get_target_longitudes(remap_info, target_field)
            stat = file_output_write_field(output_handle, target_field, frame=0)
            stat = free_target_field(target_field)
        end if

    
        !
        ! Loop over all times in the input file
        !
        do iRec=1,nRecordsIn
            stat = scan_input_rewind(handle)
    
            !
            ! Scan through list of fields in the input file, remapping fields and writing
            ! them to the output file
            !
            do while (scan_input_next_field(handle, field) == 0) 
                if (can_remap_field(field) .and. &
                    should_remap_field(field, include_field_list, exclude_field_list)) then
                    write(0,*) 'Remapping field '//trim(field % name)//', frame ', irec
    
                    call timer_start(read_timer)
                    stat = scan_input_read_field(field, frame=iRec)
                    call timer_stop(read_timer)
                    write(0,'(a,f10.6,a)') '    read: ', timer_time(read_timer), ' s'
    
                    call timer_start(remap_timer)
                    stat = remap_field(remap_info, field, target_field)
                    call timer_stop(remap_timer)
                    write(0,'(a,f10.6,a)') '    remap: ', timer_time(remap_timer), ' s'
    
                    call timer_start(write_timer)
                    stat = file_output_write_field(output_handle, target_field, frame=(nRecordsOut+iRec))
                    call timer_stop(write_timer)
                    write(0,'(a,f10.6,a)') '    write: ', timer_time(write_timer), ' s'
    
                    stat = free_target_field(target_field)
                end if
                stat = scan_input_free_field(field)
            end do
        end do
    
        nRecordsOut = nRecordsOut + nRecordsIn
        stat = scan_input_close(handle)
    end do


    !
    ! Cleanup
    !
    stat = file_output_close(output_handle)

    stat = mpas_mesh_free(source_mesh)
    stat = target_mesh_free(destination_mesh)
    stat = remap_info_free(remap_info)
    stat = field_list_finalize(include_field_list, exclude_field_list)

    call timer_stop(total_timer)

    write(0,*) ' '
    write(0,'(a,f10.6)') 'Total runtime: ', timer_time(total_timer)
    write(0,*) ' '

    stop

end program convert_mpas
