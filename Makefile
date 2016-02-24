FC = gfortran
FFLAGS = -O2 -ffree-form
FCINCLUDES = -I${NETCDF}/include
FCLIBS = -L${NETCDF}/lib -lnetcdff -lnetcdf

.SUFFIXES: .F .o

OBJS = \
	scan_input.o \
	mpas_mesh.o \
	convert_mpas.o

all: $(OBJS)
	$(FC) -o convert_mpas $(OBJS) $(FCLIBS)

convert_mpas.o: scan_input.o mpas_mesh.o

mpas_mesh.o: scan_input.o

scan_input.o:

clean:
	rm -f *.mod *.o convert_mpas

.F.o:
	rm -f $@ $*.mod
	$(FC) $(FFLAGS) -c $*.F $(FCINCLUDES)
