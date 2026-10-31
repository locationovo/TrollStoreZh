UNAME_S := $(shell uname -s 2>/dev/null)
JBROOT_DIR := $(shell find /var/containers/Bundle/Application/ -maxdepth 1 -name '.jbroot-*' -print -quit 2>/dev/null)

ifneq ($(JBROOT_DIR),)
  SDK ?= $(JBROOT_DIR)/usr/share/SDKs/iPhoneOS.sdk
  CC  := clang
else ifeq ($(UNAME_S),Darwin)
  SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
  CC  := $(shell xcrun --sdk iphoneos -f clang 2>/dev/null)
else
  SDK ?=
  CC  := clang
endif

ARCH := arm64
ifeq ($(ROOTHIDE),1)
    PKG_ARCH := iphoneos-arm64e
else
    PKG_ARCH := iphoneos-arm64
endif

BASE_VER := $(shell cat VERSION 2>/dev/null || echo "0.0.1")
GIT_HASH := $(shell git rev-parse --short HEAD 2>/dev/null || echo "nogit")
GIT_DIRTY := $(shell git diff --quiet 2>/dev/null || echo "-dirty")
VERSION := $(BASE_VER)-$(GIT_HASH)$(GIT_DIRTY)

TARGET := TrollStoreZh_$(ARCH).dylib
OBJS := main_$(ARCH).o

ifneq ($(SDK),)
CFLAGS += -arch $(ARCH) -mios-version-min=14.0 -isysroot "$(SDK)"
LDFLAGS += -arch $(ARCH) -mios-version-min=14.0 -isysroot "$(SDK)"
endif

CFLAGS += -O2 -Wall -Wextra -fPIC -fobjc-arc
LDFLAGS += -dynamiclib -framework Foundation -framework UIKit -framework CoreGraphics

.PHONY: all clean deb FORCE

all: lang_data.h $(TARGET)

lang_data.h: trollstore_zh.plist
	@echo "  GEN $@"
	@echo "#ifndef LANG_DATA_H" > $@
	@echo "#define LANG_DATA_H" >> $@
	@echo "static const char *embedded_plist_b64 = " >> $@
	@cat trollstore_zh.plist | base64 | tr -d '\n' | sed 's/.*/  "&"/' >> $@
	@echo ";" >> $@
	@echo "#endif" >> $@

$(TARGET): main.m lang_data.h FORCE
	@echo "  CC  $< ($(ARCH)) (Version: $(VERSION))"
	@$(CC) $(CFLAGS) -c main.m -o main_$(ARCH).o
	@echo "  LD  $@"
	@$(CC) $(LDFLAGS) -o $@ $(OBJS)
	@ldid -Sentitlements.plist $@

FORCE:

deb: all
	@echo "  PKG  TrollStoreZh_$(PKG_ARCH).deb (Version: $(VERSION))"
	@rm -rf layout
	@mkdir -p layout/DEBIAN layout/usr/lib/TweakInject layout/Library/MobileSubstrate/DynamicLibraries layout/var/jb/usr/lib/TweakInject layout/var/jb/Library/MobileSubstrate/DynamicLibraries "layout/var/mobile/Library/Application Support/TrollStoreZh"
	@sed -e 's/^Version: .*/Version: $(VERSION)/' -e 's/Architecture: .*/Architecture: $(PKG_ARCH)/g' control > layout/DEBIAN/control
	@cp $(TARGET) layout/usr/lib/TweakInject/TrollStoreZh.dylib
	@cp $(TARGET) layout/var/jb/usr/lib/TweakInject/TrollStoreZh.dylib
	@cp TrollStoreZh.plist layout/Library/MobileSubstrate/DynamicLibraries/TrollStoreZh.plist
	@cp TrollStoreZh.plist layout/var/jb/Library/MobileSubstrate/DynamicLibraries/TrollStoreZh.plist
	@cp trollstore_zh.plist "layout/var/mobile/Library/Application Support/TrollStoreZh/zh-Hans.plist"
	@dpkg-deb -b layout TrollStoreZh_$(PKG_ARCH).deb
	@echo "  [OK] Package created."
	@rm -rf layout

clean:
	@echo "  CLEAN"
	@rm -rf $(OBJS) $(TARGET) lang_data.h layout TrollStoreZh_*.deb
	@find . -type f \( -name "*.o" -o -name "*.d" \) -delete
