.SUFFIXES:
.SUFFIXES:  .cpp .hpp .c++ .c++m .test.c++ .o
.DEFAULT_GOAL = all

ifeq ($(MAKELEVEL),0)

ifndef OS
OS = $(shell uname -s)
endif

ifeq ($(OS),Linux)
CC = /usr/lib/llvm-19/bin/clang
CXX = /usr/lib/llvm-19/bin/clang++
CXXFLAGS = -pthread -I/usr/lib/llvm-19/include/c++/v1
LDFLAGS = -lc++ -L/usr/lib/llvm-19/lib/c++
endif

ifeq ($(OS),Darwin)
# Prefer /usr/local/llvm if available, otherwise use Homebrew LLVM
LLVM_PREFIX := $(shell if [ -d /usr/local/llvm ]; then echo "/usr/local/llvm"; elif [ -d /opt/homebrew/opt/llvm ]; then echo "/opt/homebrew/opt/llvm"; else echo ""; fi)
ifeq ($(LLVM_PREFIX),)
$(error LLVM not found. Please install LLVM at /usr/local/llvm or: brew install llvm)
endif
CC = $(LLVM_PREFIX)/bin/clang
CXX = $(LLVM_PREFIX)/bin/clang++
# Check if LLVM has its own libc++ (Homebrew) or uses system libc++ (/usr/local/llvm)
LLVM_HAS_LIBCXX := $(shell test -d $(LLVM_PREFIX)/include/c++/v1 && echo yes || echo no)
# deps/std wraps system headers, so we need to include libc++ headers
# The is_clock guard in src/std.c++m prevents redefinition when libc++ already provides it
ifeq ($(LLVM_HAS_LIBCXX),yes)
CXXFLAGS = -I$(LLVM_PREFIX)/include/c++/v1
LDFLAGS = -L$(LLVM_PREFIX)/lib/c++ -L$(LLVM_PREFIX)/lib -Wl,-rpath,$(LLVM_PREFIX)/lib/c++ -Wl,-rpath,$(LLVM_PREFIX)/lib -lc++
else
CXXFLAGS =
LDFLAGS =
endif
endif

ifeq ($(OS),Github)
CC = /usr/local/opt/llvm/bin/clang
CXX = /usr/local/opt/llvm/bin/clang++
CXXFLAGS = -I/usr/local/opt/llvm/include/ -I/usr/local/opt/llvm/include/c++/v1
LDFLAGS = -L/usr/local/opt/llvm/lib/c++ -Wl,-rpath,/usr/local/opt/llvm/lib/c++
endif

CXXFLAGS += -std=c++23 -stdlib=libc++
CXXFLAGS += -Wall -Wextra -Wno-reserved-module-identifier
LDFLAGS += -fuse-ld=lld

endif #($(MAKELEVEL),0)

 PREFIX ?= .
sourcedir = src
objectdir = $(PREFIX)/obj
binarydir = $(PREFIX)/bin
moduledir = $(PREFIX)/pcm
librarydir = $(PREFIX)/lib

# Module-specific flags (apply regardless of how compiler was configured)
# Note: deps/std wraps system headers in a module, so it needs access to system headers
# The is_clock guard in src/std.c++m prevents redefinition when libc++ already provides it
# Remove -nostdinc++ if present (deps/std needs system headers)
CXXFLAGS := $(filter-out -nostdinc++,$(CXXFLAGS))
CXXFLAGS += -fprebuilt-module-path=$(moduledir)
CXXFLAGS += -I$(sourcedir)

# For this submodule, ensure experimental library flag is present to match other modules
# and pin target triple on Darwin to ensure libc++ builtins and headers match the target.
ifeq ($(filter -fexperimental-library,$(CXXFLAGS)),)
CXXFLAGS += -fexperimental-library
endif
ifeq ($(OS),Darwin)
CXXFLAGS += -target arm64-apple-macosx14.0
LDFLAGS += -target arm64-apple-macosx14.0
endif

programs = main
library = $(librarydir)/libstd.a
.PRECIOUS: $(moduledir)/%.pcm

targets = $(programs:%=$(binarydir)/%)
test-sources = $(wildcard $(sourcedir)/*test.c++)
test-objects = $(test-sources:$(sourcedir)%.c++=$(objectdir)%.o) $(test-program:%=$(objectdir)/%.o)

sources = $(filter-out $(programs:%=$(sourcedir)/%.c++) $(test-sources), $(wildcard $(sourcedir)/*.c++))
modules = $(wildcard $(sourcedir)/*.c++m)
objects = $(modules:$(sourcedir)%.c++m=$(objectdir)%.o) $(sources:$(sourcedir)%.c++=$(objectdir)%.o)

$(moduledir)/%.pcm: $(sourcedir)/%.c++m
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $< --precompile -o $@

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

.PHONY: all
all: module

.PHONY: module
module: $(library)

.PHONY: test
test: $(test-objects) $(targets)

.PHONY: clean
clean:
	rm -rf $(objectdir) $(binarydir) $(moduledir)

.PHONY: dump
dump:
	$(foreach v, $(sort $(.VARIABLES)), $(if $(filter file,$(origin $(v))), $(info $(v)=$($(v)))))
	@echo ''
