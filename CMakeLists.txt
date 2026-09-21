cmake_minimum_required(VERSION 3.16)

# ===========================================================================
#  ITensor v3 -- CMake **打包**工程
#
#  这个工程不编译任何源文件, 也不链接任何东西。它只做一件事:
#  把 ITensor 自带的 Makefile 已经编好的产物
#
#      ITensor/lib/libitensor.a      (release,  make build)
#      ITensor/lib/libitensor-g.a    (debug,    make debug)
#      ITensor/itensor/config.h      (由 make configure 生成)
#      ITensor/itensor/**/*.h        (头文件, 位于源码树根部)
#
#  封装成一个标准的 CMake package, 使任何工程都能:
#
#      find_package(ITensor REQUIRED)
#      target_link_libraries(myapp PRIVATE ITensor::itensor)
#
#  >>> 边界约定 (重要) <<<
#  编译器 / BLAS 后端 / 优化参数 / -D 宏 仍然完全由 ITensor/options.mk 决定,
#  由 `cd ITensor && make` 负责。本工程**不参与** ITensor 的编译, 只是把
#  既成事实(options.mk 的内容 + 产物的位置)翻译成 CMake 能理解的形式。
#  下游工程通过 find_package 拿到的东西里, 已经包含了本该由 options.mk
#  传达的全部信息(BLAS 的 -I/-D/-L/-l/-fopenmp、rpath), 所以下游不必、
#  也不应该再关心 ITensor 是怎么编出来的。
#
#  用法
#  ----
#  A. 源码树导出 (同一工作区内的工程直接可用, 不需要 install)
#
#       cmake -S ITensor -B ITensor/build-cmake
#         -> 生成 ITensor/lib/cmake/ITensor/ITensorConfig.cmake 等
#       # 下游: 让 CMAKE_PREFIX_PATH 或 ITensor_DIR 指向 ITensor/ 即可
#
#  B. 安装到独立前缀 (给工作区之外的工程用)
#
#       cmake --install ITensor/build-cmake --prefix /some/where
#         -> /some/where/{include/itensor, lib/libitensor*.a, lib/cmake/ITensor}
#
#  A 和 B 共用同一份生成的 package 文件 —— 路径在 find_package 时按
#  "相对自身位置上溯" 的方式计算, 所以两种布局都能用。
#
#  注意: A 是幂等的, 可以反复执行; 改了 options.mk 并重新 make 之后,
#        重新跑一次 A (或 make cmake-package) 就能刷新 package 内容。
# ===========================================================================

project(ITensor LANGUAGES NONE)

include(CMakePackageConfigHelpers)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ParseOptionsMk)

set(ITENSOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")

# 安装目录布局。
# 这里刻意不用 include(GNUInstallDirs): 本工程没有启用任何编译语言 (因为
# 它不编译任何东西), 而 GNUInstallDirs 在不知道目标架构时无法推断 libdir,
# 会给出 CMake Warning (dev)。用两个显式变量更干净, 而且生成的 package
# 在 find_package 时会同时搜 lib/lib64/lib32, 改这两个变量也不会失配。
set(ITENSOR_INSTALL_INCLUDEDIR "include" CACHE STRING
    "安装时头文件目录 (相对 CMAKE_INSTALL_PREFIX)")
set(ITENSOR_INSTALL_LIBDIR "lib" CACHE STRING
    "安装时库目录 (相对 CMAKE_INSTALL_PREFIX)")

# ---------------------------------------------------------------------------
# 0. 版本号
#    源码树里没有版本元数据 (无 VERSION 文件、上游分支没有 git tag),
#    因此优先从 git tag 推断, 推断不出来就用一个约定值, 并允许显式覆盖:
#        cmake -S ITensor -B ITensor/build-cmake -DITENSOR_PACKAGE_VERSION=3.1.11
# ---------------------------------------------------------------------------
find_package(Git QUIET)

set(_itensor_revision "unknown")
set(_itensor_default_version "3.1.0")
if(GIT_FOUND)
  execute_process(COMMAND "${GIT_EXECUTABLE}" describe --always --dirty --abbrev=8
                  WORKING_DIRECTORY "${ITENSOR_ROOT}"
                  OUTPUT_VARIABLE _itensor_revision
                  OUTPUT_STRIP_TRAILING_WHITESPACE
                  ERROR_QUIET RESULT_VARIABLE _git_rc)
  if(NOT _git_rc EQUAL 0)
    set(_itensor_revision "unknown")
  endif()

  execute_process(COMMAND "${GIT_EXECUTABLE}" describe --tags --match "v[0-9]*" --abbrev=0
                  WORKING_DIRECTORY "${ITENSOR_ROOT}"
                  OUTPUT_VARIABLE _itensor_tag
                  OUTPUT_STRIP_TRAILING_WHITESPACE
                  ERROR_QUIET RESULT_VARIABLE _git_tag_rc)
  if(_git_tag_rc EQUAL 0 AND _itensor_tag MATCHES "^v?([0-9]+\\.[0-9]+(\\.[0-9]+)?)")
    set(_itensor_default_version "${CMAKE_MATCH_1}")
  endif()
endif()

set(ITENSOR_PACKAGE_VERSION "${_itensor_default_version}" CACHE STRING
    "写进 CMake package 的版本号 (find_package(ITensor <版本>) 用它做兼容性判断)")

set(ITENSOR_GIT_REVISION "${_itensor_revision}")

# ---------------------------------------------------------------------------
# 1. 产物: 静态库 + config.h
# ---------------------------------------------------------------------------
set(ITENSOR_RELEASE_LIB "${ITENSOR_ROOT}/lib/libitensor.a" CACHE FILEPATH
    "release 版静态库 (由 ITensor/Makefile 的 `make build` 生成)")
set(ITENSOR_DEBUG_LIB "${ITENSOR_ROOT}/lib/libitensor-g.a" CACHE FILEPATH
    "debug 版静态库 (由 ITensor/Makefile 的 `make debug` 生成); 允许不存在")

if(NOT EXISTS "${ITENSOR_ROOT}/itensor/config.h")
  message(FATAL_ERROR
    "找不到 ${ITENSOR_ROOT}/itensor/config.h\n"
    "ITensor 还没有被配置/编译过。请先:\n"
    "    cd ${ITENSOR_ROOT}\n"
    "    cp options.mk.sample options.mk   # 仅首次, 然后按需编辑\n"
    "    make\n")
endif()

set(ITENSOR_HAS_RELEASE_LIB FALSE)
set(ITENSOR_HAS_DEBUG_LIB FALSE)
if(EXISTS "${ITENSOR_RELEASE_LIB}")
  set(ITENSOR_HAS_RELEASE_LIB TRUE)
endif()
if(EXISTS "${ITENSOR_DEBUG_LIB}")
  set(ITENSOR_HAS_DEBUG_LIB TRUE)
endif()

if(NOT ITENSOR_HAS_RELEASE_LIB AND NOT ITENSOR_HAS_DEBUG_LIB)
  message(FATAL_ERROR
    "找不到 ITensor 静态库, 无法打包:\n"
    "    ${ITENSOR_RELEASE_LIB}\n"
    "    ${ITENSOR_DEBUG_LIB}\n\n"
    "请先在 ${ITENSOR_ROOT} 下编译:\n"
    "    cd ${ITENSOR_ROOT}\n"
    "    make            # release + debug 都编 (ITensor 顶层 Makefile 的默认目标)\n"
    "    make build      # 只编 release\n")
endif()

if(NOT ITENSOR_HAS_RELEASE_LIB)
  message(STATUS "ITensor 打包: 未找到 ${ITENSOR_RELEASE_LIB}, 不导出 RELEASE 配置")
endif()
if(NOT ITENSOR_HAS_DEBUG_LIB)
  message(STATUS "ITensor 打包: 未找到 ${ITENSOR_DEBUG_LIB}, 不导出 DEBUG 配置")
endif()

# ---------------------------------------------------------------------------
# 2. 从 itensor/config.h 读出平台宏 (只用于信息展示/记录)
#    注意: 这些宏本来就写在 config.h 里, 会随头文件自动传播给下游,
#          所以这里**不需要**、也**不应该**再把它们塞进 package 的编译宏。
# ---------------------------------------------------------------------------
file(READ "${ITENSOR_ROOT}/itensor/config.h" _itensor_config_h)

set(ITENSOR_PLATFORM "unknown")
if(_itensor_config_h MATCHES "#define[ \t]+PLATFORM_([A-Za-z0-9_]+)")
  set(ITENSOR_PLATFORM "${CMAKE_MATCH_1}")
endif()

# ---------------------------------------------------------------------------
# 3. 从 options.mk 解析 BLAS/LAPACK 依赖
#    options.mk 是 ITensor 构建配置的唯一真源, 这里只"读"不"写"。
#    刻意不提供 cache 覆盖: 想换 BLAS 后端就去改 options.mk (编库本来也必须
#    改它), 然后重新 make + 重新跑本工程, 避免出现"库和链接参数不一致"。
# ---------------------------------------------------------------------------
if(NOT EXISTS "${ITENSOR_ROOT}/options.mk")
  message(FATAL_ERROR
    "找不到 ${ITENSOR_ROOT}/options.mk\n"
    "它是 ITensor 构建配置的唯一真源, 打包时必须读它才能知道该链哪套 BLAS/LAPACK。\n"
    "    cd ${ITENSOR_ROOT} && cp options.mk.sample options.mk\n")
endif()

itensor_parse_options_mk("${ITENSOR_ROOT}/options.mk" ITENSOR_OPTIONS_MK)

set(ITENSOR_BLAS_INCLUDE_DIRS        "${ITENSOR_OPTIONS_MK_INCLUDE_DIRS}")
set(ITENSOR_BLAS_LINK_DIRS           "${ITENSOR_OPTIONS_MK_LINK_DIRS}")
set(ITENSOR_BLAS_LIBS                "${ITENSOR_OPTIONS_MK_LIBS}")
set(ITENSOR_BLAS_COMPILE_DEFINITIONS "${ITENSOR_OPTIONS_MK_COMPILE_DEFINITIONS}")
set(ITENSOR_BLAS_COMPILE_OPTIONS     "${ITENSOR_OPTIONS_MK_COMPILE_OPTIONS}")
set(ITENSOR_BLAS_LINK_OPTIONS        "${ITENSOR_OPTIONS_MK_LINK_OPTIONS}")

if(NOT ITENSOR_BLAS_LIBS)
  message(WARNING
    "没能从 ${ITENSOR_ROOT}/options.mk 解析出任何 BLAS/LAPACK 库。\n"
    "生成的 package 仍可用, 但下游需要自己提供 BLAS/LAPACK。")
endif()

# ---------------------------------------------------------------------------
# 4. 生成 CMake package
#    A) 源码树导出: <ITENSOR_ROOT>/lib/cmake/ITensor/
#       这个位置本身就是 CMake 约定的搜索路径
#       (<prefix>/lib/cmake/<name>/<name>Config.cmake), 所以
#       把 ITENSOR_ROOT 放进 CMAKE_PREFIX_PATH / ITensor_DIR 即可找到。
#    B) install 时把同一批文件装到 <prefix>/lib/cmake/ITensor/。
#    两种布局的目录深度相同 (上溯 3 级到前缀), 因此 package 文件不需要区分。
# ---------------------------------------------------------------------------
set(ITENSOR_PACKAGE_DIR "${ITENSOR_ROOT}/lib/cmake/ITensor")
file(MAKE_DIRECTORY "${ITENSOR_PACKAGE_DIR}")

# 4a. 其余部分是"静态"的: 路径全部在 find_package 时按相对位置计算
configure_file("${ITENSOR_ROOT}/cmake/ITensorTargets.cmake.in"
               "${ITENSOR_PACKAGE_DIR}/ITensorTargets.cmake"
               COPYONLY)

# 4b. 版本文件, 供 find_package(ITensor <版本>) 使用
write_basic_package_version_file(
  "${ITENSOR_PACKAGE_DIR}/ITensorConfigVersion.cmake"
  VERSION "${ITENSOR_PACKAGE_VERSION}"
  COMPATIBILITY SameMajorVersion)

# 4c. Config 文件: 需要把版本、平台、BLAS 参数固化进去
configure_file("${ITENSOR_ROOT}/cmake/ITensorConfig.cmake.in"
               "${ITENSOR_PACKAGE_DIR}/ITensorConfig.cmake"
               @ONLY)

# ---------------------------------------------------------------------------
# 5. 安装规则 (可选, 供 "B" 用法)
#
# 头文件用 install(DIRECTORY) 整树拷贝, 只按后缀白名单过滤。
# 不要只写 "*.h": ITensor 里还有 21 个 .hpp (itensor/util/h5/*.hpp),
# 而 itensor/qn.h 是**无条件** #include "itensor/util/h5/wrap_h5.hpp" 的
# (即使没开 HDF5), 漏装就会在下游编译时报 "没有那个文件或目录"。
# 顺带装上 .hh/.hxx/.ipp/.inc/.tcc, 免得以后加了新后缀又踩同一个坑。
# ---------------------------------------------------------------------------
install(DIRECTORY "${ITENSOR_ROOT}/itensor/"
        DESTINATION "${ITENSOR_INSTALL_INCLUDEDIR}/itensor"
        FILES_MATCHING
          PATTERN "*.h"
          PATTERN "*.hpp"
          PATTERN "*.hh"
          PATTERN "*.hxx"
          PATTERN "*.ipp"
          PATTERN "*.inc"
          PATTERN "*.tcc")

if(ITENSOR_HAS_RELEASE_LIB)
  install(FILES "${ITENSOR_RELEASE_LIB}"
          DESTINATION "${ITENSOR_INSTALL_LIBDIR}" RENAME libitensor.a)
endif()
if(ITENSOR_HAS_DEBUG_LIB)
  install(FILES "${ITENSOR_DEBUG_LIB}"
          DESTINATION "${ITENSOR_INSTALL_LIBDIR}" RENAME libitensor-g.a)
endif()

install(FILES
          "${ITENSOR_PACKAGE_DIR}/ITensorConfig.cmake"
          "${ITENSOR_PACKAGE_DIR}/ITensorConfigVersion.cmake"
          "${ITENSOR_PACKAGE_DIR}/ITensorTargets.cmake"
        DESTINATION "${ITENSOR_INSTALL_LIBDIR}/cmake/ITensor")

# ---------------------------------------------------------------------------
# 6. 汇报
# ---------------------------------------------------------------------------
message(STATUS "")
message(STATUS "ITensor CMake package")
message(STATUS "  版本         : ${ITENSOR_PACKAGE_VERSION}  (git: ${ITENSOR_GIT_REVISION})")
message(STATUS "  平台宏       : PLATFORM_${ITENSOR_PLATFORM}   (来自 itensor/config.h, 随头文件自动传播)")
message(STATUS "  release 库   : ${ITENSOR_RELEASE_LIB}")
message(STATUS "  debug 库     : ${ITENSOR_DEBUG_LIB}")
message(STATUS "  BLAS 头      : ${ITENSOR_BLAS_INCLUDE_DIRS}")
message(STATUS "  BLAS 库目录  : ${ITENSOR_BLAS_LINK_DIRS}")
message(STATUS "  BLAS 库      : ${ITENSOR_BLAS_LIBS}")
message(STATUS "  BLAS 编译宏  : ${ITENSOR_BLAS_COMPILE_DEFINITIONS}")
message(STATUS "  BLAS 选项    : ${ITENSOR_BLAS_COMPILE_OPTIONS} ${ITENSOR_BLAS_LINK_OPTIONS}")
message(STATUS "  package 位置 : ${ITENSOR_PACKAGE_DIR}")
message(STATUS "")
message(STATUS "  下游用法:")
message(STATUS "      list(APPEND CMAKE_PREFIX_PATH \"${ITENSOR_ROOT}\")")
message(STATUS "      find_package(ITensor REQUIRED)")
message(STATUS "      target_link_libraries(myapp PRIVATE ITensor::itensor)")
message(STATUS "")
message(STATUS "  安装到独立前缀 (可选):")
message(STATUS "      cmake --install ${CMAKE_BINARY_DIR} --prefix <prefix>")
message(STATUS "")
