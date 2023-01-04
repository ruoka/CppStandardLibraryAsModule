.SUFFIXES:
.SUFFIXES:  .cpp .hpp .c++ .c++m .test.c++ .o
.DEFAULT_GOAL = all

ifeq ($(MAKELEVEL),0)

ifndef OS
OS = $(shell uname -s)
endif

ifeq ($(OS),Linux)
CC = /usr/lib/llvm-15/bin/clang
CXX = /usr/lib/llvm-15/bin/clang++
CXXFLAGS = -pthread -I/usr/lib/llvm-15/include/c++/v1
LDFLAGS = -lc++ -lc++experimental -L/usr/lib/llvm-15/lib/c++
endif

ifeq ($(OS),Darwin)
CC = /opt/homebrew/opt/llvm/bin/clang
CXX = /opt/homebrew/opt/llvm/bin/clang++
CXXFLAGS =-I/opt/homebrew/opt/llvm/include/c++/v1
LDFLAGS = -L/opt/homebrew/opt/llvm/lib/c++
endif

ifeq ($(OS),Github)
CC = /usr/local/opt/llvm/bin/clang
CXX = /usr/local/opt/llvm/bin/clang++
CXXFLAGS = -I/usr/local/opt/llvm/include/ -I/usr/local/opt/llvm/include/c++/v1
LDFLAGS = -L/usr/local/opt/llvm/lib/c++ -Wl,-rpath,/usr/local/opt/llvm/lib/c++
endif

CXXFLAGS += -std=c++20 -stdlib=libc++
CXXFLAGS += -fprebuilt-module-path=$(moduledir)
CXXFLAGS += -Wall -Wextra
CXXFLAGS += -I$(sourcedir)
LDFLAGS += -fuse-ld=lld

endif #($(MAKELEVEL),0)

CXXFLAGS += -fexperimental-library
LDFLAGS += -fexperimental-library

sourcedir = src
objectdir = obj
moduledir = pcm
librarydir = lib
binarydir = bin

programs = main
library = $(librarydir)/libstd.a

targets = $(programs:%=$(binarydir)/%)
test-sources = $(wildcard $(sourcedir)/*test.c++)
test-objects = $(test-sources:$(sourcedir)%.c++=$(objectdir)%.o) $(test-program:%=$(objectdir)/%.o)
sources = $(filter-out $(programs:%=$(sourcedir)/%.c++) $(test-sources), $(wildcard $(sourcedir)/*.c++))
modules = $(wildcard $(sourcedir)/*.c++m)
objects = $(modules:$(sourcedir)%.c++m=$(objectdir)%.o) $(sources:$(sourcedir)%.c++=$(objectdir)%.o)

dependencies = $(objectdir)/Makefile.deps

$(moduledir)/%.pcm: $(sourcedir)/%.c++m
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $< --precompile -c -o $@

$(objectdir)/%.o: $(moduledir)/%.pcm
	@mkdir -p $(@D)
	$(CXX) $< -c -o $@

$(objectdir)/%.impl.o: $(sourcedir)/%.impl.c++
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $< -fmodule-file=$(moduledir)/$(basename $(basename $(@F))).pcm -c -o $@

$(objectdir)/%.test.o: $(sourcedir)/%.test.c++
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $< -c -o $@

$(objectdir)/%.o: $(sourcedir)/%.c++
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $< -c -o $@

$(objectdir)/%.o: $(sourcedir)/%.cpp
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $< -c -o $@

$(binarydir)/%: $(sourcedir)/%.c++ $(objects) $(libraries)
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $^ -o $@

$(library) : $(objects)
	@mkdir -p $(@D)
	$(AR) $(ARFLAGS) $@ $^

$(dependencies):
	@mkdir -p $(@D)
#c++m module wrapping headers etc.
	grep -HE '[ ]*export[ ]+module' $(sourcedir)/*.c++m | sed -E 's/.+\/([a-z_0-9\-]+)\.c\+\+m.+/$(objectdir)\/\1.o: $(moduledir)\/\1.pcm/' > $(dependencies)
#c++m module interface unit
	grep -HE '[ ]*import[ ]+([a-z_0-9]+)' $(sourcedir)/*.c++m | sed -E 's/.+\/([a-z_0-9\-]+)\.c\+\+m:[ ]*import[ ]+([a-z_0-9]+)[ ]*;/$(moduledir)\/\1.pcm: $(moduledir)\/\2.pcm/' >> $(dependencies)
#c++m module partition unit
	grep -HE '[ ]*import[ ]+:([a-z_0-9]+)' $(sourcedir)/*.c++m | sed -E 's/.+\/([a-z_0-9]+)(\-*)([a-z_0-9]*)\.c\+\+m:.*import[ ]+:([a-z_0-9]+)[ ]*;/$(moduledir)\/\1\2\3.pcm: $(moduledir)\/\1\-\4.pcm/' >> $(dependencies)
#c++m module impl unit
	grep -HE '[ ]*module[ ]+([a-z_0-9]+)' $(sourcedir)/*.c++ | sed -E 's/.+\/([a-z_0-9\.\-]+)\.c\+\+:[ ]*module[ ]+([a-z_0-9]+)[ ]*;/$(objectdir)\/\1.o: $(moduledir)\/\2.pcm/' >> $(dependencies)
#c++ source code
	grep -HE '[ ]*import[ ]+([a-z_0-9]+)' $(sourcedir)/*.c++ | sed -E 's/.+\/([a-z_0-9\.\-]+)\.c\+\+:[ ]*import[ ]+([a-z_0-9]+)[ ]*;/$(objectdir)\/\1.o: $(moduledir)\/\2.pcm/' >> $(dependencies)

-include $(dependencies)

.PHONY: all
all: module

.PHONY: module
module: $(dependencies) $(library)

.PHONY: test
test: $(dependencies) $(test-objects) $(targets)

.PHONY: clean
clean:
	rm -rf $(objectdir) $(binarydir) $(moduledir)

.PHONY: dump
dump:
	$(foreach v, $(sort $(.VARIABLES)), $(if $(filter file,$(origin $(v))), $(info $(v)=$($(v)))))
	@echo ''
