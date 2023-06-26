OUTPUT ?= $(abspath output)
CLANG ?= CLANG
LLVM_STRIP ?= llvm-LLVM_STRIP
BPFTOOL_PATH ?= $(abspath bpftool)
BPFTOOL_SRC := $(abspath ./bpftool/src)
BPFTOOL_OUTPUT ?= $(abspath $(OUTPUT)/bpftool)
BPFTOOL ?= $(BPFTOOL_OUTPUT)/bootstrap/bpftool
LIBBPF_PATH ?= $(abspath libbpf)
LIBBPF_SRC := $(abspath ./libbpf/src)
LIBBPF_OBJ := $(abspath $(OUTPUT)/libbpf.a)
INCLUDES := -I$(OUTPUT) -I./libbpf/include/uapi
CFLAGS := -g -O2 -
BPFCFLAGS := -g -O2 -Wall
LDFLAGS := -static
INSTALL ?= install
prefix ?= /usr/local

EXECUTABLE := memtrace

FUNCS := memtrace
SRCS := memtrace.c trace_helpers.c syscall_helpers.c errno_helpers.c map_helpers.c uprobe_helpers.c

OBJS := $(SRCS:.c=.o)

$(EXECUTABLE): $(LIBBPF_OBJ) $(BPFTOOL) $(OBJS)
	@echo [Link] $@ FROM: $^
	@mkdir -p $(OUTPUT)/bin
	@$(CC) $^ $(LDFLAGS) $(LIBBPF_OBJ) -lelf -lz -lm -o $(OUTPUT)/bin/$@

.c.o:
	@echo [Compile C] $<
	@$(CC) -o $@ $< -c $(CFLAGS) $(INCLUDES)

$(OUTPUT)/%.skel.h: $(OUTPUT)/%.bpf.o | $(OUTPUT) $(BPFTOOL)
	$(call msg,GEN-SKEL,$@)
	$(Q)$(BPFTOOL) gen skeleton $< > $@

$(OUTPUT)/%.bpf.o: %.bpf.c $(LIBBPF_OBJ) $(wildcard %.h) $(ARCH)/vmlinux.h | $(OUTPUT)
	$(call msg,BPF,$@)
	$(Q)$(CLANG) $(BPFCFLAGS) -target bpf -D__TARGET_ARCH_$(ARCH)	      \
		     -I$(ARCH)/ $(INCLUDES) -c $(filter %.c,$^) -o $@ &&      \
	$(LLVM_STRIP) -g $@

$(BPFTOOL): | $(BPFTOOL_OUTPUT)
	$(call msg,BPFTOOL,$@)
	$(Q)ln -fs $(LIBBPF_SRC) $(BPFTOOL_SRC)/../libbpf/src
	$(Q)$(MAKE) ARCH= CROSS_COMPILE= OUTPUT=$(BPFTOOL_OUTPUT)/ -C $(BPFTOOL_SRC) bootstrap

$(LIBBPF_OBJ): $(wildcard $(LIBBPF_SRC)/*.[ch])
    $(call msg,GIT,$@)
	$(Q)[ -d "$(LIBBPF_PATH)" ] || git clone -q https://github.com/libbpf/libbpf.git $(LIBBPF_PATH)
	$(Q)cd $(LIBBPF_PATH) && git pull
	@echo [Compile LIBBPF]
	@mkdir -p $(OUTPUT)/libbpf
	@$(MAKE) -C $(LIBBPF_SRC) BUILD_STATIC_ONLY=1		      \
		OBJDIR=$(dir $@)/libbpf DESTDIR=$(dir $@)		      \
		INCLUDEDIR= LIBDIR= UAPIDIR= NO_PKG_CONFIG=1		  \
		install

clean:
	@echo [Remove $(OUTPUT) dir and .o files]
	@rm -rf $(OUTPUT) *.o
