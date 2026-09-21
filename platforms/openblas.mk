### 平台参数文件: OpenBLAS 0.3.28
###
### 用途
###   覆盖 ITensor/options.mk, 然后重建 ITensor 与本工程:
###
###     cp platforms/openblas.mk ITensor/options.mk
###     cd ITensor && make clean && make build && make cmake-package
###     cd .. && cmake --build build -j
###
###   运行前先 export OPENBLAS_NUM_THREADS=4 / OMP_NUM_THREADS=1.
###   bench_* 程序会把当前环境变量打印在结果表上方.
###
### 说明
###   OpenBLAS 自带的 lapacke.h 通过 lapack.h 间接包含 lapacke_config.h,
###   而 lapack.h 只在定义了 HAVE_LAPACK_CONFIG_H 时才这么做. 不定义时会
###   走 C99 _Complex 分支, ITensor 把 lapack_complex_double 按 double[2]
###   重解释, 正好也是对的; 这里按上游 options.mk.sample 的写法固定成
###   struct 形式, 保证与库二进制内部的约定明确一致.
###
###   -DHAVE_LAPACK_CONFIG_H 与 -DLAPACK_COMPLEX_STRUCTURE 属于 ABI 相关宏,
###   会随 options.mk 一起被翻译进 CMake package 的 INTERFACE 属性, 下游
###   工程不需要重复添加.
###
###   本文件是唯一在编译期带 -fpermissive 的平台 (上游 sample 如此写).
###


#########
## [1] 编译器
#########
CCCOM=g++ -m64 -std=c++17 -fPIC


#########
## [2] BLAS / LAPACK
#########
PLATFORM=openblas
OPENBLASROOT=/app/ITensor/OpenBLAS-0.3.28
BLAS_LAPACK_INCLUDEFLAGS=-I$(OPENBLASROOT)/include \
                         -fpermissive -DHAVE_LAPACK_CONFIG_H -DLAPACK_COMPLEX_STRUCTURE
BLAS_LAPACK_LIBFLAGS=-L$(OPENBLASROOT)/lib -lopenblas -lpthread


#########
## [3] HDF5 (可选，默认关闭)
#########
#HDF5_PREFIX=/usr


#########
## [4] ITensor 自带 OpenMP 多线程 (可选，默认关闭)
##     启用后运行前请设置: export OMP_NUM_THREADS=8
#########
#ITENSOR_USE_OMP=1


#########
## [5] 编译优化 / 调试开关
#########
OPTIMIZATIONS=-O3 -DNDEBUG -Wall -Wno-unknown-pragmas
DEBUGFLAGS=-DDEBUG -g -Wall -Wno-unknown-pragmas -pedantic

## 设为 1 则额外生成动态库 libitensor.so（本项目用静态库，保持 0）
ITENSOR_MAKE_DYLIB=0


###
### 以下为 ITensor 内部使用的派生变量，一般无需修改
###

PREFIX=$(THIS_DIR)

ITENSOR_LIBDIR=$(PREFIX)/lib
ITENSOR_INCLUDEDIR=$(PREFIX)

ITENSOR_LIBNAMES=itensor
ITENSOR_LIBFLAGS=$(patsubst %,-l%, $(ITENSOR_LIBNAMES))
ITENSOR_LIBFLAGS+= $(BLAS_LAPACK_LIBFLAGS)
ITENSOR_LIBGFLAGS=$(patsubst %,-l%-g, $(ITENSOR_LIBNAMES))
ITENSOR_LIBGFLAGS+= $(BLAS_LAPACK_LIBFLAGS)
ITENSOR_LIBS=$(patsubst %,$(ITENSOR_LIBDIR)/lib%.a, $(ITENSOR_LIBNAMES))
ITENSOR_GLIBS=$(patsubst %,$(ITENSOR_LIBDIR)/lib%-g.a, $(ITENSOR_LIBNAMES))

ITENSOR_INCLUDEFLAGS=-I'$(ITENSOR_INCLUDEDIR)' $(BLAS_LAPACK_INCLUDEFLAGS)

ifdef HDF5_PREFIX
ITENSOR_USE_HDF5 = 1
ITENSOR_INCLUDEFLAGS += -I$(HDF5_PREFIX)/include -DITENSOR_USE_HDF5
ITENSOR_LIBFLAGS += -L$(HDF5_PREFIX)/lib -lhdf5 -lhdf5_hl
ITENSOR_LIBGFLAGS += -L$(HDF5_PREFIX)/lib -lhdf5 -lhdf5_hl
endif

ifndef CCCOM
$(error Makefile variable CCCOM not defined in options.mk; please define it.)
endif

ifdef ITENSOR_USE_OMP
ITENSOR_INCLUDEFLAGS += -DITENSOR_USE_OMP -fopenmp
ITENSOR_LIBFLAGS += -fopenmp
ITENSOR_LIBGFLAGS += -fopenmp
endif

CCFLAGS=-I. $(ITENSOR_INCLUDEFLAGS) $(OPTIMIZATIONS) -Wno-unused-variable
CCGFLAGS=-I. $(ITENSOR_INCLUDEFLAGS) $(DEBUGFLAGS)
LIBFLAGS=-L'$(ITENSOR_LIBDIR)' $(ITENSOR_LIBFLAGS)
LIBGFLAGS=-L'$(ITENSOR_LIBDIR)' $(ITENSOR_LIBGFLAGS)

## 共享库后缀
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  DYLIB_EXT ?= dylib
  DYLIB_FLAGS ?= -dynamiclib
else
  DYLIB_EXT ?= so
  DYLIB_FLAGS ?= -shared
endif
