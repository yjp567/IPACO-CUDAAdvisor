#include<sys/mman.h>
#include<assert.h>

#include<iostream>
#include<string.h>
#include "../common.h"
#include "types.h"

//#include<unordered_map>
//#include<cuda.h>

// --- Add Constant Memory for Line Range ---
__constant__ int d_targetStartLine = -1; // Default: -1 means measure all lines
__constant__ int d_targetEndLine = -1;

__device__ int CTALB = 0; 		//the lower bound of CTA id you want to profile
__device__ int CTAUB = 99999;		//the upper bound of CTA id you want to profile 
__device__ int CONSTANCE = 128;
__device__ int aliveCTA = 0;

//__device__ std::unordered_map< std::string, long> blockmap;
//__device__ std::vector<int> testt;  		//this DOESN'T work //"dynamic initialization doesn't work for __device__

__device__ bool VERBOSE=false;
__device__ bool CALLPATHVERBOSE=false;

extern "C"
{	//so that no mangling for function names
	__device__ void takeString(void* , int);
	__device__ void RetKernel(void*);
	__device__ void passBasicBlock(int, int, int, int, void*);
	__device__ void print5(void*, int, int, int, int, void*);
	__device__ void print4(void*);
	__device__ void callFunc(void* , void* , int , int, void*);
	__device__ int getContextID(void*);
	__device__ void* InitKernel(void*);
	__device__ void print1(int);
}

__device__ unsigned long long ccnntt = 1;		//the very first element is reserved for metadata
__device__ unsigned long long bbccnntt = 1;		//the very first element is reserved for metadata

__device__ int* buffer_oN_DeViCe;		//should be multiples of 6
//__device__ int* globalCallStack;
//__device__ CallSite_t* globalCallStack;
//__device__ int* stackHeight;
 

__device__ char funcDic[UNIQUE_FUNC_DEVICE][FUNC_NAME_LEN];       //maintains 100 unique functions and 31 chars for each
__device__ int dicHeight = 0;				// size of funcDic[][]

__device__ CallSite_t contextDic[TOTAL_NUMBER_CONTEXT][CALL_PATH_LEN_DEVICE]; //maintains 100 unique contexts, each has up to 10 function
__device__ int cHeight = 0;



__device__ void mystrcpy(char* dst, char* src)
{
	int cnt = 0;
	while ( src[cnt] != '\0' && cnt < FUNC_NAME_LEN-1) //never exceeds this 30 limit
	{
		dst[cnt] = src[cnt];
		cnt++;
	}
	dst[cnt] = '\0';
	return;
}

__device__ bool mystrcmp(char* dst, char* src)
{
        int cnt = 0;
        while ( cnt < FUNC_NAME_LEN-1 ) //never exceeds this 30 limit
        {
		if ( dst[cnt] == '\0' && src[cnt] == '\0')
			return true;

                if (dst[cnt] != src[cnt])
			return false;
                cnt++;
        }
        return true;
}

__device__ int getFuncID(char* func)
{
	if (dicHeight == 0 ) //the very first function
	{
		mystrcpy(funcDic[0], func);
//		printf("src: %s\n", func);
//		printf("dst: %s\n", funcDic[0]);
		dicHeight ++;
		return 0;
	}

//	printf("d: height = %d\n", dicHeight);
	for(int i=0; i < dicHeight; i++)
	{
		bool found = mystrcmp( funcDic[i],  func );
//		printf("d:: compare this pair: %s: \t%s \tVS\t %s\n", found?"yes":"no", funcDic[i], func);
		if(found)
			return i;
	}

	//return -1;//DEBUG	
	//if you are here, means we have a new func
	mystrcpy(funcDic[dicHeight], func); 
	dicHeight ++;
	return dicHeight-1;
}

__device__ void updateCallStack(int caller, int callee, short sline, short scolm, int bid, int tid, void* p_stackzone)
{
	int offset = bid*blockDim.x*blockDim.y+tid;
//	CallSite_t* callStack = (CallSite_t*) (&(globalCallStack[offset*CALL_PATH_LEN_DEVICE]));
//	int &height = stackHeight[offset];

	CallSite_t* callStack = (CallSite_t*) p_stackzone;
	int bytesPerThread = (CALL_PATH_LEN_DEVICE*sizeof(CallSite_t));
	int* temp = (int*)( (char*)p_stackzone + bytesPerThread+16);	//offset by 16 to be safe, need to be consistent
	int &height = *temp;		

//	int &h11 = * (int*)( (char*)p_stackzone + bytesPerThread);		
	
//	if(CALLPATHVERBOSE)
//		printf( ":::::::: height = %d :::::::::\n", height);

//	assert(height != 1 && "stack height != 1") ;

	//return;//DUBUG
        if (height==0)
        {
//		if (CALLPATHVERBOSE)
//			printf("first ever. tid=%d\n", tid);
		callStack[0].id = caller;
		callStack[0].sline = sline;
		callStack[0].scolm = scolm;
		
		callStack[1].id = callee;
                callStack[1].sline = -1;
                callStack[1].scolm = -1;
		height=2;
                return;
        }

        int p_caller = callStack[height-2].id;
        int p_callee = callStack[height-1].id;

        if ( p_caller == caller && p_callee == callee)
        {       //repeated call
//		if (CALLPATHVERBOSE)
//			printf("repeated call\n");
                callStack[height-2].sline = sline;
                callStack[height-2].scolm = scolm;
                return;
        }
        else if ( p_caller == caller && p_callee != callee)
        {       //the same parent called a different function, simply update the callee
//		if (CALLPATHVERBOSE)
//      		printf("same caller different callee\n");
                callStack[height-1].id = callee;
                callStack[height-2].sline = sline;
                callStack[height-2].scolm = scolm;
                return;
        }
        else if ( p_callee == caller)
        {       // a typical call path
//		if (CALLPATHVERBOSE)
//			printf("call sequence\n");
                callStack[height-1].sline = sline;
                callStack[height-1].scolm = scolm;

                callStack[height].id = callee;
                callStack[height].sline = -1;
                callStack[height].scolm = -1;
		height++;
                return;
        }
//	return;//DUBUG

//	if (CALLPATHVERBOSE)
//		printf("the caller exists deeply in the stack\n");
	// the caller exists deeply in the stack
       	for (int i=height-1; i>=0; i--)
        {
                if ( callStack[i].id == caller)
                {
			height = i+1;
                        callStack[i].id = callee;
                        callStack[i].sline = -1;
                        callStack[i].scolm = -1;

                        callStack[i].sline = sline;
                        callStack[i].scolm = scolm;
                        return;
                }
        }

        // the caller exists deeply in the stack
//	assert( (0==-1) && "!! undefined things happeened here\n");
}



__device__ void* InitKernel(void* ptrhead)
{
	//TODO:
	if ( (blockIdx.x + blockIdx.y*gridDim.x) < CTALB || (blockIdx.x + blockIdx.y*gridDim.x) > CTAUB) // you only need a few CTAs
		return NULL; 

        int tid = threadIdx.x + threadIdx.y *blockDim.x;
        int bid = blockIdx.x + blockIdx.y * gridDim.x;
        int global_tid = tid + bid*blockDim.x*blockDim.y;
	int num_cta = gridDim.x*gridDim.y;
	int num_thread = blockDim.x*blockDim.y;

	__shared__ char* handler;	//this pointer is for maintaing stack/callpath
	__syncthreads();
	int bytesPerThread = sizeof(CallSite_t)*CALL_PATH_LEN_DEVICE + 32;// I put 32 just to be safe
	if ( tid ==0 )
	{
		handler = (char*) malloc( blockDim.x*blockDim.y*bytesPerThread); 
		assert( handler!=NULL);
//		printf(" CTA \t%d\tgrabs memroy\t%p\n", bid, handler);
		int rank = atomicAdd( &aliveCTA, 1);
		printf(" CTA\t%d\tonline, total alive\t%d\n", bid, rank);
		if (rank==0)
		{
		//	if (tid%32==0)
			{
		//		buffer_oN_DeViCe = (int*)ptrhead;
				printf("\nd: InitKernel...\n");
				printf("d: buffer pointer: %p\n", buffer_oN_DeViCe);
				printf("d: size of kernel grid: %d, %d\t%d, %d\n", gridDim.x, gridDim.y, blockDim.x, blockDim.y);
			}
		}
		if (rank == 1)
			buffer_oN_DeViCe = (int*)ptrhead;
	}	
	__syncthreads();

	void* stackzone = (void*)( handler + bytesPerThread*tid );

	return stackzone;


} 

__device__ void callFunc(void* er, void* ee, int sline, int scolm, void* p_stackzone)
{
	if (p_stackzone == NULL)
		return;
//	if (threadIdx.x != 0 || blockIdx.x != 0 || threadIdx.y != 0 || blockIdx.y != 0) 	return;	//DEBUG

//	printf("d::%d\n", sline );
//	printf("d::%s\n", (char*)er );

//	if (CALLPATHVERBOSE)
//		printf("d:::: >>>>\n");
	int id1 = getFuncID( (char*)er );
	int id2 = getFuncID( (char*)ee );
//	if (CALLPATHVERBOSE)
//	{
//		printf("d:::: ID: %d :%s\n", id1, (char*)er );
//		printf("d:::: ID: %d :%s\n", id2, (char*)ee );
//	}

	int tid = threadIdx.y * blockDim.x + threadIdx.x;
        int bid = blockIdx.x + blockIdx.y * gridDim.x;
        int global_tid = bid * (blockDim.x * blockDim.y) + tid;

	updateCallStack(id1, id2, (short) sline, (short) scolm, bid, tid, p_stackzone);
//	printCallStack(global_tid);

//	if (CALLPATHVERBOSE)
//		printf("d:::: <<<<\n");
}



__device__ void cxtprint(int id)
{
	if (id<0)
		return;

	printf("d::: requested context id: %d out of %d\n", id, cHeight);

	for (int i = 0; i< CALL_PATH_LEN_DEVICE  && contextDic[id][i].id != -1  ; i++)
	{
		printf("d::::::: current context [%d][%d]: %d, %d, %d\n", id, i, contextDic[id][i].id, contextDic[id][i].sline, contextDic[id][i].scolm) ;
	}

	return;
}

__device__ void cxtcpy( CallSite_t* dst, CallSite_t* src , int height) //context copy 
{

	int i;
	for( i=0; i< height; i++)
		dst[i] = src[i];

//	assert(i<CALL_PATH_LEN_DEVICE && "code: e56: call stack too deep");

	dst[i].id = -1; //to mark the ending of one context

	return;
}


__device__ bool cxtcmp( CallSite_t* dst, CallSite_t* src, int height)
{
	for( int i=0; i< height; i++)
		if ( dst[i].id == src[i].id ) // && dst[i].id == src[i].id && 	
			continue;
		else
			return false;

	return true;
}


__device__ int getContextID(void* p_stackzone)
{	//shared by all treahds, there are races
	//you can manually to take care of serialization?

//	if (threadIdx.x + threadIdx.y + blockIdx.x + blockIdx.y != 0 ) 		return -2; //DEBUG

	int bid = blockIdx.x + blockIdx.y * gridDim.x; 
	int tid = threadIdx.y * blockDim.x + threadIdx.x;

//	int offset = bid*blockDim.x*blockDim.y+tid;
//	CallSite_t* callStack = (CallSite_t*) (&(globalCallStack[offset*CALL_PATH_LEN_DEVICE]));
//      int &height = stackHeight[offset];

        CallSite_t* callStack = (CallSite_t*) p_stackzone;
	int bytesPerThread = (CALL_PATH_LEN_DEVICE*sizeof(CallSite_t));
	int* temp = (int*)( (char*)p_stackzone + bytesPerThread+16);	//offset by 8 to be safe, need to be consistent
	int &height = *temp;

	if ( height ==0) //it is possible that call stack is still empty
		return -1;

	if (cHeight==0)// the first ever context in the dic
	{
//		if (CALLPATHVERBOSE)
//			printf("d::: the very first context in dic, depth=%d\n", height);
		cxtcpy(contextDic[0], callStack, height );
		cHeight=1;
		return 0;
	}

	// something already exists
//	if (CALLPATHVERBOSE)
//	{
//		printf("d::: going to match existing items in context dic\n");
//		printf("d::: number of existing contexts: %d\n", cHeight);
//	}
	int i;
	for (i = 0; i<cHeight; i++)
	{
		if ( cxtcmp(  contextDic[i], callStack, height ) ) //yes, found
		{
//			if (CALLPATHVERBOSE)
//				printf("d::: matched, returning %d,  depth=%d\n",i, height);
			return i; 
		}
	}

//	if (CALLPATHVERBOSE)
//		printf("d::: not found, value of i: %d\n", i);

//	assert (i< TOTAL_NUMBER_CONTEXT && "code:e34: Not enough space for Context Dic, index i");
//	printCallStack();

	cxtcpy(contextDic[i], callStack, height );
	cHeight = i+1;
//	assert (cHeight < TOTAL_NUMBER_CONTEXT && "code:e41: Not enough space for Context Dic, cHeight");
	
//	if (CALLPATHVERBOSE)
//		printf("d::: inserted new one: id = %d, depth=%d\n", i, height);
	return i;	
}


__device__ void passBasicBlock(int tmp /*pointer to block name*/, int action, int sline, int scolm, void* p_stackzone)
{
        if ( (blockIdx.x + blockIdx.y*gridDim.x) < CTALB || (blockIdx.x + blockIdx.y*gridDim.x) > CTAUB) // you only need a few CTAs
                return;

	int map = __ballot_sync(0xFFFFFFFF, 1);
	int numActive = __popc(map);

	if ( buffer_oN_DeViCe == NULL)
		return;


	if (numActive==32)
	{
		//then choose one thread to write numbers
		int tid = threadIdx.x + threadIdx.y *blockDim.x;
		if (tid%32==0)
		{	
			//do the writing
			//	printf("I will write for my warp tid=(%d, %d)\n", threadIdx.x, threadIdx.y);
			int bid = atomicAdd(&bbccnntt, 1);
			unsigned long long key=0;

			BBlog_t* bblog = (BBlog_t*) buffer_oN_DeViCe;
			bblog[bid].key = key;

			bblog[bid].tidx = (short)threadIdx.x;
			bblog[bid].tidy = (short)threadIdx.y;
			bblog[bid].bidx = (short)blockIdx.x;
			bblog[bid].bidy = (short)blockIdx.y;
			bblog[bid].sline = sline;
			bblog[bid].scolm = scolm;

			bblog[bid].cid = getContextID(p_stackzone);
		}

	} 
	else
	{
		//every thread needs to write
		//printf("I will write for my self tid=(%d, %d)\n", threadIdx.x, threadIdx.y);
                        int bid = atomicAdd(&bbccnntt, 1);
                        unsigned long long key=0;

                        BBlog_t* bblog = (BBlog_t*) buffer_oN_DeViCe;
			bblog[bid].key = key;

                        bblog[bid].tidx = (short)threadIdx.x;
                        bblog[bid].tidy = (short)threadIdx.y;
                        bblog[bid].bidx = (short)blockIdx.x;
                        bblog[bid].bidy = (short)blockIdx.y;
                        bblog[bid].sline = sline;
                        bblog[bid].scolm = scolm;

                        bblog[bid].cid = getContextID(p_stackzone);
	}

        return;
}



__device__ void storeLines(void* p, short size/*bytes*/, short line, short colmn, short op /*load or store*/, void* p_stackzone)
{
        if ( (blockIdx.x + blockIdx.y*gridDim.x) < CTALB || (blockIdx.x + blockIdx.y*gridDim.x) > CTAUB) // you only need a few CTAs
                return;

        int map = __ballot_sync(0xFFFFFFFF, 1);
        int numActive = __popc(map);

	if ( ccnntt >  (int)(((long)BUFFERSIZE)/24) - 128*100)
		return; //DEBUG
	
	assert ( (ccnntt < BUFFERSIZE/24 - 128) && "code: e31: too many entries to the buffer"); //DO NOT COMMENT OUT
	
	int bid = atomicAdd(&ccnntt, 1);

	//d_trace[bid].bidx = blockIdx.x;
	//d_trace[bid].tidx = threadIdx.x;
	//d_trace[bid].ea = p;
	//d_trace[bid].bytes = size;
	//printf(" d : bid = %d from (%d,%d) (%d,%d) \n", bid, blockIdx.x, threadIdx.x, blockIdx.y, threadIdx.y);

	if (buffer_oN_DeViCe==NULL)
		return;

	if( true)
	{
		int tid = threadIdx.x + threadIdx.y *blockDim.x;
		if ( tid%32==0 || true)
		{

			short* buffer_oN_DeViCe_short = (short*) buffer_oN_DeViCe;
			long* buffer_oN_DeViCe_long = (long*) buffer_oN_DeViCe;

			buffer_oN_DeViCe_short[bid*12+0] = (short)blockIdx.x;
			buffer_oN_DeViCe_short[bid*12+1] = (short)blockIdx.y;
			buffer_oN_DeViCe_short[bid*12+2] = (short)threadIdx.x;
			buffer_oN_DeViCe_short[bid*12+3] = (short)threadIdx.y;
			buffer_oN_DeViCe_long[bid*3+1] = (long)p;
			buffer_oN_DeViCe_short[bid*12+8] = size;
			buffer_oN_DeViCe_short[bid*12+9] = line;
			buffer_oN_DeViCe_short[bid*12+10] = colmn;
			buffer_oN_DeViCe_short[bid*12+11] = op;
			getContextID(p_stackzone);
		}	
	}
}



__device__ void print1(int a)
{
	if (threadIdx.x + threadIdx.y + blockIdx.x + blockIdx.y == 0)
		printf("d: print1: %d\n", a);

	return;
	if (threadIdx.x + threadIdx.y + blockIdx.x + blockIdx.y == 0 && VERBOSE)
	{	
		if (a==1)
			printf("d: load by CTA (%d,%d)\n", blockIdx.x, blockIdx.y);
		else if (a==2)
			printf("d: store by CTA (%d,%d)\n", blockIdx.x, blockIdx.y);
		else
			printf("d: !!! undefined !!! \n" );
	}	
}

/*
__device__ void print2()
{
	if (threadIdx.x + threadIdx.y + blockIdx.x + blockIdx.y == 0 && VERBOSE)
        	printf("d: store by CTA (%d,%d)\n", blockIdx.x, blockIdx.y);
}
*/

__device__ void print3(int line, int col)
{
	return;
	if (threadIdx.x + threadIdx.y + blockIdx.x + blockIdx.y == 0 && VERBOSE)
        	printf("d: source line: %d\t column: %d by CTA (%d,%d)\n", line, col, blockIdx.x, blockIdx.y);
}

__device__ void print4(void* p)
{
        //if (threadIdx.x + threadIdx.y + blockIdx.x + blockIdx.y == 0 && VERBOSE)

	printf("d: print4: %p\n", p);

}

__device__ void print5(void* p, int bits, int sline, int scolm, int op, void* p_stackzone)
{
//	if ( (blockIdx.x  + blockIdx.y* gridDim.x) * (blockDim.x * blockDim.y) >= 32*128) // no more than 128 warps
//		return;
//	printf("d: ea: %p by (%d,%d) (%d,%d), CTA id = %d\n",p, blockIdx.x, threadIdx.x, blockIdx.y, threadIdx.y , (blockIdx.x  + blockIdx.y* gridDim.x));

	if ( (blockIdx.x + blockIdx.y*gridDim.x) < CTALB || (blockIdx.x + blockIdx.y*gridDim.x) > CTAUB) // you only need a few CTAs 
		return;

			bool isInRange = (d_targetStartLine == -1 || d_targetEndLine == -1 || (sline >= d_targetStartLine && sline <= d_targetEndLine));
			if (isInRange)
			{return;}
        storeLines(p, (short)(bits/8), (short)sline, (short) scolm, (short)op, p_stackzone);
//	printf("d: ea: %p by (%d,%d) (%d,%d), CTA id = %d\n",p, blockIdx.x, threadIdx.x, blockIdx.y, threadIdx.y , (blockIdx.x  + blockIdx.y* gridDim.x));
//	printf("d: ea: %p by (%d,%d) (%d,%d)\n",p, blockIdx.x, threadIdx.x, blockIdx.y, threadIdx.y );

}

////
__device__ void RetKernel(void* p_stackzone)
{
	if ( (blockIdx.x + blockIdx.y*gridDim.x) < CTALB || (blockIdx.x + blockIdx.y*gridDim.x) > CTAUB) // you only need a few CTAs 
		return;

        int bid = blockIdx.x + blockIdx.y * gridDim.x;
        int tid = threadIdx.x + threadIdx.y *blockDim.x;


	__syncthreads();	//IMPORTANT to sync here
	int rank = -1;
	if ( tid == 0)
	{
	//	printf(" CTA\t%d\treleases:\t%p\n", bid, stackzone);
	//	atomicAdd( &alive, -1);
		if (p_stackzone!=NULL)
		{
			free(p_stackzone);
			rank = atomicAdd( &aliveCTA, -1);
			printf("CTA\t%d\texits, total remains\t%d\n", bid, rank);
		}
		else
			printf("d:: p_stack is hacked!!\n");
	}
	__syncthreads();

	if (threadIdx.x + threadIdx.y == 0 && rank ==1 )
	{
		printf("d: in RetKernel...\n");

//                for (int kk=0; kk< cHeight; kk++)
//                        cxtprint( kk );

		if (true)
		{	//memory
			short* buffer_oN_DeViCe_short = (short*) buffer_oN_DeViCe;
			buffer_oN_DeViCe_short[0+0] = blockDim.x; // Be consistent with print.cpp, dumpTrace()
			buffer_oN_DeViCe_short[0+1] = blockDim.y;
			buffer_oN_DeViCe_short[0+2] = gridDim.x;
			buffer_oN_DeViCe_short[0+3] = gridDim.y;
			printf("d: Kernel Returns: collected [ %llu ] memory entries. \n" , ccnntt);
			printf("d: Kernel Returns: collected [ %llu ] memory entries. \n" , bbccnntt);

			long* buffer_oN_DeViCe_long = (long*) buffer_oN_DeViCe;
			buffer_oN_DeViCe_long[0+1] = ccnntt;
		}
		else
		{	//branch
			BBlog_t* bbbuffer_oN_DeViCe_short = (BBlog_t*) buffer_oN_DeViCe;
			bbbuffer_oN_DeViCe_short[0].bidx = blockDim.x; // Be consistent with print.cpp, dumpTrace()
			bbbuffer_oN_DeViCe_short[0].bidy = blockDim.y;
			bbbuffer_oN_DeViCe_short[0].tidx = gridDim.x;
			bbbuffer_oN_DeViCe_short[0].tidy = gridDim.y;
			bbbuffer_oN_DeViCe_short[0].key = bbccnntt;
			bbbuffer_oN_DeViCe_short[0].sline = 0;
			bbbuffer_oN_DeViCe_short[0].scolm = 0;
			printf("d: Kernel Returns: collected [ %llu ] BB logs. \n" , bbccnntt);
			printf("d: Kernel Returns: collected [ %llu ] BB logs. \n" , ccnntt);
		}

		unsigned long offset1 = ((UNIQUE_FUNC_DEVICE* FUNC_NAME_LEN*sizeof(char))/1024+1)*1024;
		unsigned long offset2 = ((TOTAL_NUMBER_CONTEXT * CALL_PATH_LEN_DEVICE* sizeof(CallSite_t))/1024+1)*1024 + offset1;

		printf("size of function dic: %d %d %lu -> %lu , rounded to %lu\n", UNIQUE_FUNC_DEVICE, FUNC_NAME_LEN, sizeof(char), UNIQUE_FUNC_DEVICE*FUNC_NAME_LEN*sizeof(char), offset1 );

                printf("size of context dic: %d %d %lu -> %lu , rounded to %lu\n", TOTAL_NUMBER_CONTEXT, CALL_PATH_LEN_DEVICE, sizeof(CallSite_t), TOTAL_NUMBER_CONTEXT* CALL_PATH_LEN_DEVICE* sizeof(CallSite_t) , offset2);


		//function dic is the last, 
		//context dic is second to last
		void* ptr;
		ptr = (void*)( buffer_oN_DeViCe + (BUFFERSIZE - offset1)/sizeof(int)) ; //operate on a int*, not a void*

		memcpy( ptr, funcDic, UNIQUE_FUNC_DEVICE *FUNC_NAME_LEN*sizeof(char) );

		ptr = (void*)(buffer_oN_DeViCe + (BUFFERSIZE - offset2)/sizeof(int)) ; //operate on a int*, not a void*
		memcpy( ptr, contextDic, TOTAL_NUMBER_CONTEXT * CALL_PATH_LEN_DEVICE*sizeof(CallSite_t) );
		ccnntt = 1; //reset, prepares for next kernel call
		bbccnntt = 1; //reset, prepares for next kernel call

	}//end of if

        

}

