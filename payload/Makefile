PS5_HOST ?=
PORT     ?= 9021
PWSH     ?= pwsh
# Build identity. VERSION is the released version and VERSION_CODE the numeric
# code written to the startup banner and to the report field poords4_rc.
# Development builds of the next version are produced by passing an incremental
# beta number: the artifact then carries the semver prerelease suffix (CI
# classifies a *-beta* tag as a prerelease and never as the repository "latest").
#   make -C payload release          -> PoorDS4-v1.1.0.elf
#   make -C payload BETA=1 release   -> PoorDS4-v1.1.0-beta.1.elf
VERSION      := 1.1.0
VERSION_CODE := 110
BETA         ?= 0
ifeq ($(filter 0,$(BETA)),)
BUILD_VERSION := $(VERSION)-beta.$(BETA)
else
BUILD_VERSION := $(VERSION)
endif

TARGET        := PoorDS4-v$(BUILD_VERSION).elf
STATUS_TARGET := PoorDS4-status.elf
STOP_TARGET   := PoorDS4-stop.elf

ifndef PS5_PAYLOAD_SDK
$(error PS5_PAYLOAD_SDK is not set)
endif

include $(PS5_PAYLOAD_SDK)/toolchain/prospero.mk

# Use prospero-clang from the SDK bin directory
CC := prospero-clang
STRIP := llvm-strip

CFLAGS  += -D__PROSPERO__ -Wall -Wextra -Wshadow -Wunreachable-code \
	-Werror -g -O2 -fPIC \
	-fno-stack-protector -ffunction-sections -fdata-sections \
	-fdebug-compilation-dir=.
LDFLAGS      += -Wl,--gc-sections,--build-id=sha1
RUNTIME_LIBS := -nodefaultlibs -lc -lkernel_web -lSceLibcInternal
BRIDGE_LIBS  := $(RUNTIME_LIBS) -lSceUserService

.PHONY: all audit clean deploy release status stop

all: $(TARGET)

$(TARGET): game_pad_bridge_main.c wireless_ds4.c wireless_ds4.h pad_types.h
	$(CC) $(CFLAGS) -DPOORDS4_AUTO_WATCH=1 \
		'-DPOORDS4_VERSION_STR="$(BUILD_VERSION)"' \
		-DPOORDS4_VERSION_CODE=$(VERSION_CODE) -o $@ \
		game_pad_bridge_main.c wireless_ds4.c $(LDFLAGS) $(BRIDGE_LIBS)

status: $(STATUS_TARGET)

$(STATUS_TARGET): game_pad_bridge_status_main.c wireless_ds4.c \
	wireless_ds4.h pad_types.h
	$(CC) $(CFLAGS) -o $@ game_pad_bridge_status_main.c wireless_ds4.c \
		$(LDFLAGS) $(RUNTIME_LIBS)

stop: $(STOP_TARGET)

$(STOP_TARGET): stop_game_pad_bridge_main.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS) $(RUNTIME_LIBS)

release: all status stop
	$(STRIP) --strip-debug $(TARGET) $(STATUS_TARGET) $(STOP_TARGET)

audit:
	@if command -v $(PWSH) >/dev/null 2>&1; then \
		$(PWSH) -NoProfile -File ../tests/static-audit.ps1; \
	else \
		echo "pwsh not found: skipping the static audit (set PWSH=...)"; \
	fi

clean:
	rm -f PoorDS4-v*.elf PoorDS4rc*.elf PoorDS4exp.elf \
		$(STATUS_TARGET) $(STOP_TARGET)

deploy: $(TARGET)
ifndef PS5_HOST
	$(error PS5_HOST is not set)
endif
	nc -w 8 $(PS5_HOST) $(PORT) < $(TARGET)
