SM =sm_86
CP =compute_86
LLVM = /home/yash/Yash/Sem_6/IPACO/llvm-project

PASS =$(LLVM)/build/lib/LLVMCudaAdvisor.so
UPATH =$(LLVM)/llvm/lib/Transforms/CUDAAdvisor/src/
clang = $(LLVM)/build/bin/clang-14 -isystem /usr/include/c++/10 -isystem /usr/include/x86_64-linux-gnu/c++/10 -isystem /usr/include/cuda
llvm-link = $(LLVM)/build/bin/llvm-link
opt = $(LLVM)/build/bin/opt -enable-new-pm=0
llc = $(LLVM)/build/bin/llc
cuda = /usr/lib/cuda
