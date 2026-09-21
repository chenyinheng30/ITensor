#
# Makefile for ITensor libraries
#
####################################

include options.mk

# 编 release 库 libitensor.a, 下游用到的就是它
build: itensor 

itensor: configure
	@echo
	@echo Building ITensor release library
	@echo
	@cd itensor && $(MAKE) build

# 编 debug 库 libitensor-g.a, 平时不需要
itensor-debug: configure
	@echo
	@echo Building ITensor debug library
	@echo
	@cd itensor && $(MAKE) debug
    

configure:
	@echo
	@echo Configure: Writing current dir to this_dir.mk
	@echo "THIS_DIR=$(PWD)" > this_dir.mk
	@echo "#ifndef __ITENSOR_CONFIG_H" > itensor/config.h
	@echo "#define __ITENSOR_CONFIG_H" >> itensor/config.h
	@echo "" >> itensor/config.h
	@echo "#ifndef PLATFORM_$(PLATFORM)" >> itensor/config.h
	@echo "#define PLATFORM_$(PLATFORM)" >> itensor/config.h
	@echo "#endif" >> itensor/config.h
	@echo "" >> itensor/config.h
	@echo "#ifndef __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES" >> itensor/config.h
	@echo "#define __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES 0" >> itensor/config.h
	@echo "#endif" >> itensor/config.h
	@echo "" >> itensor/config.h
ifdef ITENSOR_USE_HDF5
ifeq ($(ITENSOR_USE_HDF5),1)
	@echo "#ifndef ITENSOR_USE_HDF5" >> itensor/config.h
	@echo "#define ITENSOR_USE_HDF5 1" >> itensor/config.h
	@echo "#endif" >> itensor/config.h
endif
endif
	@echo "#endif " >> itensor/config.h

clean:
	@echo "Removing temporary build files"
	@touch this_dir.mk
	@cd itensor && $(MAKE) clean
	@cd sample && $(MAKE) clean
	@cd unittest && $(MAKE) clean
	@rm -rf lib/*
	@rm -f this_dir.mk
	@rm -f itensor/config.h

# 把编好的库 + 头文件导出成 CMake package, 之后的工程可以直接
#     find_package(ITensor REQUIRED)
#     target_link_libraries(app PRIVATE ITensor::itensor)
# 只用 $(CURDIR) 而不是 $(PWD): make 的 $(PWD) 在 `make -C` 下不会被更新,
# 会让 configure 把错误路径写进 this_dir.mk。
cmake-package: build
	@echo
	@echo Exporting ITensor CMake package
	@echo
	cmake -S "$(CURDIR)" -B "$(CURDIR)/build-cmake"
	@echo
	@echo Done. Downstream projects can use:
	@echo "    list(APPEND CMAKE_PREFIX_PATH \"$(CURDIR)\")"
	@echo "    find_package(ITensor REQUIRED)"
	@echo

distclean: clean
	@rm -f this_dir.mk options.mk
