# ===========================================================================
#  ParseOptionsMk.cmake
#
#  从 ITensor 自带的 options.mk 中, 提取"链接 ITensor 静态库所需的外部依赖参数"。
#
#  为什么需要它
#  ------------
#  ITensor 是 BLAS/LAPACK 的薄封装。libitensor.a 里对 mkl_* / cblas_* 等符号
#  的引用是**未解析的外部符号**, 必须由最终链接它的可执行文件提供 —— 而且必须
#  是编译 ITensor 时用的**同一个后端**(LP64 vs ILP64、threaded vs sequential、
#  MKL vs OpenBLAS...), 否则会出现符号找不到或运行期结果错误。
#
#  options.mk 是 ITensor 构建配置的唯一真源。ITensor 自己的"打包"工程
#  (ITensor/CMakeLists.txt) 在这里把它读出来, 并固化进生成的 CMake package,
#  这样下游只要
#       find_package(ITensor REQUIRED)
#       target_link_libraries(app PRIVATE ITensor::itensor)
#  就能正确链接, 不必知道 ITensor 用的是哪套 BLAS。
#
#  这段代码只在 ITensor 内部执行; 下游工程既看不到 options.mk, 也不会跑到这里。
#
#  支持的 make 语法 (够用即可, 不是一个完整的 make 解析器)
#  ------------------------------------------------------
#    * 续行      : 行尾 "\" 与下一行拼接
#    * 注释      : "#" 之后丢弃
#    * 赋值      : VAR=value    (重复赋值时最后一个胜出, 与 make 一致)
#                  VAR+=value   (追加)
#    * 变量展开  : $(VAR) 与 ${VAR}, 迭代展开至收敛 (最多 5 轮)
#
#  刻意**不**处理 ifdef / ifeq 等条件语句: 在本项目的 options.mk 里, 这些条件
#  只决定 HDF5 和 OpenMP 两个可选特性是否开启, 直接检查对应变量是否存在即可,
#  结果完全一样。
# ===========================================================================

# ---------------------------------------------------------------------------
# itensor_parse_options_mk(<options.mk 路径> <输出前缀>)
#
# 在调用者作用域中定义:
#   <前缀>_<VARNAME>             options.mk 里每个变量 (已展开) 的值
#   <前缀>_VARNAMES              收集到的变量名列表
#   <前缀>_INCLUDE_DIRS          -I 头文件目录
#   <前缀>_COMPILE_DEFINITIONS   -D 编译宏
#   <前缀>_COMPILE_OPTIONS       编译选项
#   <前缀>_LINK_DIRS             -L 库目录
#   <前缀>_LIBS                  -l 库名
#   <前缀>_LINK_OPTIONS          链接选项
# ---------------------------------------------------------------------------
function(itensor_parse_options_mk _file _out)

  set(_kind_list
      INCLUDE_DIRS
      COMPILE_DEFINITIONS
      COMPILE_OPTIONS
      LINK_DIRS
      LIBS
      LINK_OPTIONS)

  if(NOT EXISTS "${_file}")
    message(WARNING
      "ParseOptionsMk: 找不到 ${_file}\n"
      "  -> 生成的 CMake package 将**不附带**任何 BLAS/LAPACK 编译与链接参数。")
    set(${_out}_VARNAMES "" PARENT_SCOPE)
    foreach(_k IN LISTS _kind_list)
      set(${_out}_${_k} "" PARENT_SCOPE)
    endforeach()
    return()
  endif()

  file(READ "${_file}" _text)

  # 续行拼接 (make 的 "\" + 换行 => 一个空格)
  string(REGEX REPLACE "\\\\\r?\n" " " _text "${_text}")

  # --- 1. 收集 VAR=value / VAR+=value -------------------------------------
  set(_names "")
  string(REPLACE "\n" ";" _lines "${_text}")
  foreach(_line IN LISTS _lines)
    string(REGEX REPLACE "#.*" "" _line "${_line}") # 去注释 (逐行做, 因为 . 不匹配换行)
    string(STRIP "${_line}" _line)
    if(_line MATCHES "^([A-Za-z_][A-Za-z0-9_]*)[ \t]*([+]?=)[ \t]*(.*)$")
      set(_name "${CMAKE_MATCH_1}")
      set(_op "${CMAKE_MATCH_2}")
      set(_val "${CMAKE_MATCH_3}")
      string(STRIP "${_val}" _val)
      if(_op STREQUAL "+=" AND DEFINED _v_${_name})
        set(_v_${_name} "${_v_${_name}} ${_val}")
      else()
        set(_v_${_name} "${_val}")
        if(NOT "${_name}" IN_LIST _names)
          list(APPEND _names "${_name}")
        endif()
      endif()
    endif()
  endforeach()

  # --- 2. 迭代展开 $(VAR) 与 ${VAR} ---------------------------------------
  # 每个变量的值里都可能引用别的变量 (BLAS_LAPACK_LIBFLAGS -> MKLROOT),
  # 所以对每个变量都要尝试替换所有已知变量名, 直到全部收敛 (最多 5 轮)。
  # 跳过自引用, 否则值会逐轮膨胀 (make 里那样写本身也是错的)。
  foreach(_pass RANGE 4)
    set(_changed FALSE)
    foreach(_name IN LISTS _names)
      if(DEFINED _v_${_name} AND NOT "${_v_${_name}}" STREQUAL "")
        set(_before "${_v_${_name}}")
        set(_after "${_before}")
        foreach(_ref IN LISTS _names)
          if(NOT "${_ref}" STREQUAL "${_name}"
             AND DEFINED _v_${_ref} AND NOT "${_v_${_ref}}" STREQUAL "")
            string(REPLACE "$(${_ref})" "${_v_${_ref}}" _after "${_after}")
            string(REPLACE "\${${_ref}}" "${_v_${_ref}}" _after "${_after}")
          endif()
        endforeach()
        if(NOT "${_after}" STREQUAL "${_before}")
          set(_v_${_name} "${_after}")
          set(_changed TRUE)
        endif()
      endif()
    endforeach()
    if(NOT _changed)
      break()
    endif()
  endforeach()

  # --- 3. 把 flag 串拆成类别 ----------------------------------------------
  # 这个宏在调用者 (即本函数) 作用域里累积 _it_* 变量; 因此可以连续调用多次,
  # 结果会自动合并到同一组列表里, 不需要在两次调用之间清空。
  macro(_itensor_split_flags _flags)
    separate_arguments(_it_tokens UNIX_COMMAND "${_flags}")
    set(_it_i 0)
    list(LENGTH _it_tokens _it_n)
    while(_it_i LESS _it_n)
      list(GET _it_tokens ${_it_i} _it_tok)
      math(EXPR _it_i "${_it_i} + 1")
      if(_it_tok MATCHES "^-I(.+)$")
        list(APPEND _it_include_dirs "${CMAKE_MATCH_1}")
      elseif(_it_tok MATCHES "^-D(.+)$")
        list(APPEND _it_defs "${CMAKE_MATCH_1}")
      elseif(_it_tok MATCHES "^-L(.+)$")
        list(APPEND _it_ldirs "${CMAKE_MATCH_1}")
      elseif(_it_tok MATCHES "^-l(.+)$")
        list(APPEND _it_libs "${CMAKE_MATCH_1}")
      elseif(_it_tok STREQUAL "-framework")
        # "-framework Accelerate" 是两个 token 组成的一个链接选项
        if(_it_i LESS _it_n)
          list(GET _it_tokens ${_it_i} _it_fw)
          math(EXPR _it_i "${_it_i} + 1")
          list(APPEND _it_lopt "-framework" "${_it_fw}")
        endif()
      elseif(_it_tok MATCHES "^-Wl,")
        list(APPEND _it_lopt "${_it_tok}")
      elseif(_it_tok MATCHES "^-f" OR _it_tok MATCHES "^-m" OR _it_tok MATCHES "^-O")
        # -fopenmp / -m64 / -O2 这类同时影响编译和链接
        list(APPEND _it_copt "${_it_tok}")
        list(APPEND _it_lopt "${_it_tok}")
      elseif(_it_tok MATCHES "\\$[({]")
        # 没展开干净的 make 函数 (patsubst/shell/...), 忽略掉
      else()
        # 无法识别的 flag: 编译和链接都带上, 最保险
        list(APPEND _it_copt "${_it_tok}")
        list(APPEND _it_lopt "${_it_tok}")
      endif()
    endwhile()
  endmacro()

  set(_it_include_dirs "")
  set(_it_defs "")
  set(_it_copt "")
  set(_it_ldirs "")
  set(_it_libs "")
  set(_it_lopt "")

  # BLAS/LAPACK: 编译期 (-I/-D, OpenBLAS 还需要 -DHAVE_LAPACK_CONFIG_H 等)
  _itensor_split_flags("${_v_BLAS_LAPACK_INCLUDEFLAGS}")
  # BLAS/LAPACK: 链接期 (-L/-l)
  _itensor_split_flags("${_v_BLAS_LAPACK_LIBFLAGS}")

  # --- 4. 两个可选特性: 直接看 options.mk 里的开关变量 ---------------------
  # HDF5: options.mk 里 `ifdef HDF5_PREFIX` 会给 ITensor 加上 -lhdf5 -lhdf5_hl
  if(DEFINED _v_HDF5_PREFIX AND NOT "${_v_HDF5_PREFIX}" STREQUAL "")
    list(APPEND _it_include_dirs "${_v_HDF5_PREFIX}/include")
    list(APPEND _it_ldirs "${_v_HDF5_PREFIX}/lib")
    list(APPEND _it_libs "hdf5" "hdf5_hl")
  endif()

  # OpenMP: options.mk 里 `ifdef ITENSOR_USE_OMP` 会加上 -fopenmp
  if(DEFINED _v_ITENSOR_USE_OMP AND NOT "${_v_ITENSOR_USE_OMP}" STREQUAL "0")
    list(APPEND _it_copt "-fopenmp")
    list(APPEND _it_lopt "-fopenmp")
  endif()

  # --- 5. 去重并导出 ------------------------------------------------------
  foreach(_k IN ITEMS include_dirs defs copt ldirs libs lopt)
    if(_it_${_k})
      list(REMOVE_DUPLICATES _it_${_k})
    endif()
  endforeach()

  # options.mk 里的所有变量 (前缀化, 避免污染调用者命名空间)
  foreach(_name IN LISTS _names)
    set(${_out}_${_name} "${_v_${_name}}" PARENT_SCOPE)
  endforeach()

  set(${_out}_VARNAMES            "${_names}"          PARENT_SCOPE)
  set(${_out}_INCLUDE_DIRS        "${_it_include_dirs}" PARENT_SCOPE)
  set(${_out}_COMPILE_DEFINITIONS "${_it_defs}"         PARENT_SCOPE)
  set(${_out}_COMPILE_OPTIONS     "${_it_copt}"         PARENT_SCOPE)
  set(${_out}_LINK_DIRS           "${_it_ldirs}"        PARENT_SCOPE)
  set(${_out}_LIBS                "${_it_libs}"         PARENT_SCOPE)
  set(${_out}_LINK_OPTIONS        "${_it_lopt}"         PARENT_SCOPE)

endfunction()
