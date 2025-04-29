all: sbsi

DEBUG = 

OPTAPP = -O0
OPT = -O2 -std=c++14
GC = g++ -std=c++14 #for unordered_map
include ../env.mk
include testtask.mk

SRC = axpy.cu
EXE =axpy
CFLAGS = # -I/usr/lib/gcc/x86_64-linux-gnu/4.8/include/ -std=c++11
ANSF =$(UPATH)ansf.cu
HOST_SO =libprint.so

INSTRU = -instru-host-measure -instru-mem-bw -bw-start-line=-1 -bw-end-line=-1
# INSTRU = -instru-kernel-memory
#INSTRU = -instru-kernel-sig  -instru-kernel-basic -instru-kernel-call-path  -constmerge  
# INSTRU = -instru-kernel-sig -instru-kernel-basic -instru-kernel-call-path -instru-kernel-memory -constmerge

## INSTRU = -instru-kernel-sig -instru-kernel-basic -instru-kernel-call-path $(INSTRU_TASK) -constmerge

#INSTRU = -instru-kernel-sig -instru-kernel-basic -instru-kernel-call-path -instru-kernel-branch -constmerge


AUXSRC = 
AUXOBJ =

$(PASS) : $(UPATH)/../LLVM_advisor.cpp $(UPATH)/../common.h
	#cd  $(UPATH)/..; sh auto.sh;

ll : device.clean.ll ansf.ll device.link.ll device.ll device.ll device.ll host.ll hosttmp.ll hosti.ll

rsm: hosti.bc
	llvm-as < hosti.ll > hosti.bc 
	$(clang) hosti.bc -c
	$(clang) hosti.o -o axpy -L/usr/local/cuda/lib64 -lcudart -ldl -lrt -pthread -L. -lprint

AUXOBJ: $(AUXSRC)
	gcc -c < $< 

%.ll:  %.bc
	llvm-dis < $< > $@ 

native:	$(SRC)
	nvcc $(DEBUG) $(OPTAPP) $(SRC) -o native -L. -lprint --gpu-architecture=$(SM)

clang: $(SRC)
	$(clang) $(DEBUG) -G $(OPTAPP) $(SRC) -o clang --cuda-gpu-arch=$(SM) -L/usr/local/cuda/lib64 -lcudart -ldl -lrt -pthread #-save-temps

bc:
	$(clang) $(DEBUG) $(OPT) $(SRC) -emit-llvm -c -save-temps

device.bc instru: device.link.bc $(PASS) 
	$(opt) -load $(PASS) $(INSTRU) < device.link.bc > device.bc

clean: 
	rm -f *.o *.bc *.ll *.s  native_ax* *.cubin *.ptx *.fatbin a.out *.cui *cudafe* *cpp*.i* *fatbin.c *module_id *.reg.c $(EXE) native clang

$(HOST_SO) : $(UPATH)/print.cpp  $(UPATH)/../common.h $(UPATH)/types.h $(UPATH)/calc.cpp
	$(GC) -c $(DEBUG) $(OPT) -Wall -D $(ANA_TASK) -fPIC -lm -fopenmp $(UPATH)/print.cpp -o $(UPATH)/print.o
	$(GC) $(UPATH)/print.o -shared -o $(HOST_SO)

wayin:
	cp device.clean.bc device.bc

sbs: wayin device.fatbin host.bc
	$(clang) host.bc -c
	$(clang) host.o -o $(EXE) -L/usr/local/cuda/lib64 -lcudart -ldl -lrt -pthread 

aux:

sbsi: hosti.o $(HOST_SO) 
	$(clang) $(DEBUG) $(AUXOBJ) hosti.o -o $(EXE) -L/usr/local/cuda/lib64 -lcudart -ldl -lrt -lm -pthread -L$(UPATH) -lprint
	
hosti.o: hosti.bc
	$(clang) hosti.bc -c

hosttmp.bc: host.bc  $(PASS)  
	$(opt) -load $(PASS) -instru-host-sig < host.bc > hosttmp.bc	

hosti.bc: hosttmp.bc  $(PASS)
	$(opt) -load $(PASS) -instru-host -instru-host-measure -constmerge < hosttmp.bc > hosti.bc

#	$(opt) -load $(PASS) -instru-global-var < hosttmp.bc > hosttmp2.bc	
#	$(opt) -load $(PASS) -instru-host < hosttmp2.bc > hosti.bc	

host.o : host.bc
	$(clang) host.bc -c

host.bc: device.fatbin $(SRC)
	$(LLVM)/build/bin/clang++ $(OPT) -std=c++14 -c  -emit-llvm $(SRC) \
		--cuda-gpu-arch=$(SM) --cuda-path=$(cuda) \
		-I/usr/include/c++/10 -I/usr/include/x86_64-linux-gnu/c++/10
	cp axpy.bc host.bc


#	$(LLVM)/build/bin/clang-14  -cc1 -isystem /usr/include/c++/10 -isystem /usr/include/x86_64-linux-gnu/c++/10 -cc1 -triple x86_64-unknown-linux-gnu -aux-triple nvptx64-nvidia-cuda -emit-llvm-bc -emit-llvm-uselists -disable-free -main-file-name axpy.cu -mrelocation-model static -mthread-model posix -fmath-errno -mconstructor-aliases -target-cpu x86-64 -v -debug-info-kind=limited -dwarf-version=4 -debugger-tuning=gdb -resource-dir $(LLVM)/../lib/clang/4.0.0 $(OPT) -fdeprecated-macro -ferror-limit 19 -pthread -fobjc-runtime=gcc -fcxx-exceptions -fexceptions -disable-llvm-passes -o host.bc -x cuda-cpp-output host.cui -fcuda-include-gpubinary device.fatbin

#	$(LLVM)/build/bin/clang-14  -cc1 -isystem /usr/include/c++/10 -isystem /usr/include/x86_64-linux-gnu/c++/10 -isystem /usr/include/cuda/ -triple x86_64-unknown-linux-gnu -aux-triple nvptx64-nvidia-cuda -emit-llvm-bc -emit-llvm-uselists -disable-free -main-file-name axpy.cu -mrelocation-model static -mthread-model posix -fmath-errno -v -debug-info-kind=limited -dwarf-version=4 -debugger-tuning=gdb -main-file-name $(SRC) -fdeprecated-macro -ferror-limit 19 -pthread -fobjc-runtime=gcc -fcxx-exceptions -fexceptions -disable-llvm-passes -o host.bc -x cuda-cpp-output host.cui -fcuda-include-gpubinary device.fatbin

#	$(clang) -cc1 $(OPT) -triple x86_64-unknown-linux-gnu -aux-triple nvptx64-nvidia-cuda -emit-llvm-bc -emit-llvm-uselists -disable-free -main-file-name $(SRC) -o host.bc -x cuda-cpp-output host.cui -fcuda-include-gpubinary device.fatbin

#	$(LLVM)/build/bin/clang-14  -cc1 -isystem /usr/include/c++/10 -isystem /usr/include/x86_64-linux-gnu/c++/10 -isystem /usr/include/cuda/ $(OPT) -triple x86_64-unknown-linux-gnu -aux-triple nvptx64-nvidia-cuda -emit-llvm-bc -emit-llvm-uselists -disable-free -main-file-name $(SRC) -o host.bc -x cuda-cpp-output host.cui -fcuda-include-gpubinary device.fatbin	

#	$(clang) -emit-llvm-bc axpy.cu -o host.bc device.fatbin
#	$(clang) $(DEBUG) $(OPTAPP) $(CFLAGS) --cuda-host-only --cuda-gpu-arch=$(SM) --cuda-path=$(cuda) -emit-llvm -c $(SRC) -o host.bc -fcuda-include-gpubinary device.fatbin
#    $(clang) $(DEBUG) $(OPT) $(CFLAGS) --cuda-host-only --cuda-gpu-arch=$(SM) --cuda-path=$(cuda) -emit-llvm -c $(SRC) -o host.bc -fcuda-include-gpubinary device.fatbin

device.ptx: device.bc
	llc device.bc -march=nvptx64 -mcpu=sm_86 -mattr=+ptx70 -filetype=asm -o device.ptx

device.o :  device.ptx
	ptxas --gpu-name $(SM) device.ptx -o device.o -g -v -maxrregcount=31 #for verbose, resources check

device.fatbin: device.o host.cui 
	fatbinary --cuda -64 --create device.fatbin --image=profile=$(SM),file=device.o --image=profile=$(CP),file=device.ptx  

host.cui: $(SRC)
	$(clang) $(DEBUG) $(OPTAPP) $(CFLAGS) -E --cuda-host-only --cuda-gpu-arch=$(SM) --cuda-path=$(cuda) $(SRC) -o host.cui
	$(clang) $(DEBUG) $(OPTAPP) $(CFLAGS) -c --cuda-host-only --cuda-gpu-arch=$(SM) --cuda-path=$(cuda) -emit-llvm $(SRC) -o host.clean.bc
	$(clang) $(DEBUG) $(OPTAPP) $(CFLAGS) -c -S --cuda-host-only --cuda-gpu-arch=$(SM) --cuda-path=$(cuda) -emit-llvm $(SRC) -o host.clean.ll

device.clean.bc:  $(SRC)
	$(clang) $(DEBUG) $(OPTAPP) $(CFLAGS) -c --cuda-device-only --cuda-gpu-arch=$(SM) --cuda-path=$(cuda) -emit-llvm $(SRC) -o device.clean.bc

ansf.bc :  $(ANSF) $(UPATH)/../common.h  $(UPATH)/types.h
	$(clang) $(DEBUG) $(OPT) -c --cuda-device-only --cuda-gpu-arch=$(SM) --cuda-path=$(cuda) -emit-llvm $(ANSF) -o ansf.bc

device.link.bc: device.clean.bc ansf.bc 
	$(llvm-link) device.clean.bc ansf.bc -o=device.link.bc



