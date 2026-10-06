load("@rules_cc//cc:defs.bzl", "cc_library")

_ITENSOR_SRCS = [
    "itensor/decomp.cc",
    "itensor/global.cc",
    "itensor/hermitian.cc",
    "itensor/index.cc",
    "itensor/indexset.cc",
    "itensor/itdata/combiner.cc",
    "itensor/itdata/dense.cc",
    "itensor/itdata/diag.cc",
    "itensor/itdata/qcombiner.cc",
    "itensor/itdata/qdense.cc",
    "itensor/itdata/qdiag.cc",
    "itensor/itdata/scalar.cc",
    "itensor/itensor.cc",
    "itensor/mps/autompo.cc",
    "itensor/mps/mpo.cc",
    "itensor/mps/mpoalgs.cc",
    "itensor/mps/mps.cc",
    "itensor/mps/mpsalgs.cc",
    "itensor/qn.cc",
    "itensor/spectrum.cc",
    "itensor/svd.cc",
    "itensor/tagset.cc",
    "itensor/tensor/algs.cc",
    "itensor/tensor/contract.cc",
    "itensor/tensor/gemm.cc",
    "itensor/tensor/lapack_wrap.cc",
    "itensor/tensor/mat.cc",
    "itensor/tensor/vec.cc",
    "itensor/util/args.cc",
    "itensor/util/cputime.cc",
    "itensor/util/input.cc",
]

def itensor_cc_library(name, hdrs, debug = False):
    cc_library(
        name = name,
        srcs = _ITENSOR_SRCS,
        hdrs = hdrs,
        copts = [
            "-std=c++17",
            "-Wall",
            "-Wno-unknown-pragmas",
        ] + select({
            ":openmp_enabled": ["-fopenmp"],
            "//conditions:default": [],
        }),
        defines = [
            "PLATFORM_openblas",
            "__ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES=0",
        ] + (["DEBUG"] if debug else []),
        includes = ["."],
        linkopts = select({
            ":openmp_enabled": ["-fopenmp"],
            "//conditions:default": [],
        }),
        local_defines = select({
            ":openmp_enabled": ["ITENSOR_USE_OMP"],
            "//conditions:default": [],
        }),
        target_compatible_with = ["@platforms//os:linux"],
        deps = ["@openblas//:openblas"],
    )
