#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include "lang_data.h"

static NSDictionary *gDict = nil;

static void loadPlist() {
    NSString *b64 = [NSString stringWithUTF8String:embedded_plist_b64];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    NSDictionary *embeddedDict = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
    NSMutableDictionary *mergedDict = [NSMutableDictionary dictionaryWithDictionary:embeddedDict ?: @{}];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = @[
        @"/var/mobile/Library/Application Support/TrollStoreZh/zh-Hans.plist",
        @"/Library/Application Support/TrollStoreZh/zh-Hans.plist",
        @"/var/jb/Library/Application Support/TrollStoreZh/zh-Hans.plist"
    ];
    
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) {
            NSDictionary *extDict = [NSDictionary dictionaryWithContentsOfFile:path];
            if (extDict && extDict.count > 10) {
                [mergedDict addEntriesFromDictionary:extDict];
                break;
            }
        }
    }
    gDict = [mergedDict copy];
}

static id T(id s) {
    if (!s) return s;
    
    if ([s isKindOfClass:[NSAttributedString class]]) {
        NSAttributedString *attr = (NSAttributedString *)s;
        if (attr.length == 0) return s;
        
        NSString *translatedStr = T(attr.string);
        if (translatedStr != attr.string) {
            NSDictionary *attributes = [attr attributesAtIndex:0 effectiveRange:nil];
            if (attributes) {
                return [[NSAttributedString alloc] initWithString:translatedStr attributes:attributes];
            } else {
                return [[NSAttributedString alloc] initWithString:translatedStr];
            }
        }
        return s;
    }
    
    if (![s isKindOfClass:[NSString class]]) return s;
    
    NSString *str = (NSString *)s;
    
    // 去除首尾空白再匹配，防止由于换行或空格导致不匹配
    NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSString *translated = gDict[trimmed];
    if (translated) return translated;
    
    NSString *upper = [trimmed uppercaseString];
    translated = gDict[upper];
    if (translated) return translated;

    // 拦截“高级”设置页里的超长说明文本
    if ([trimmed hasPrefix:@"installd:\nInstalls applications by doing"] || [trimmed hasPrefix:@"installd:\r\nInstalls applications by doing"]) {
        return @"installd：\n通过 installd 进行占位安装，修复权限然后将其添加到图标缓存中来安装 App。\n优点：在图标缓存重载方面，可能比自定义方法更具持久性。\n缺点：似乎无缘无故地导致某些 App 出现小问题（例如，使用此方法安装时，Watusi 无法保存首选项）。";
    }
    if ([trimmed hasPrefix:@"Custom (Recommended):\nInstalls applications by manually"] || [trimmed hasPrefix:@"Custom (Recommended):\r\nInstalls applications by manually"]) {
        return @"自定义（推荐）：\n通过使用 MobileContainerManager 手动创建包，将 App 复制到其中并添加到图标缓存中来安装 App。\n优点：没有已知问题（与 installd 方法中概述的 Watusi 问题相反）。\n缺点：在图标缓存重载方面，可能比 installd 方法稍微不那么持久。";
    }
    if ([trimmed hasPrefix:@"NOTE: In cases where installd is selected but the placeholder installation fails"]) {
        return @"注意：如果选择了 installd，但占位安装失败，TrollStore 会自动回退到使用自定义方法。";
    }
    if ([trimmed hasPrefix:@"installd (Recommended):\nUninstalls applications using"] || [trimmed hasPrefix:@"installd (Recommended):\r\nUninstalls applications using"]) {
        return @"installd（推荐）：\n使用与主屏幕卸载时 SpringBoard 相同的 API 来卸载 App。";
    }
    if ([trimmed hasPrefix:@"Custom:\nUninstalls applications by removing"] || [trimmed hasPrefix:@"Custom:\r\nUninstalls applications by removing"]) {
        return @"自定义：\n通过从图标缓存中移除 App，然后直接删除其 App 包和数据包来卸载 App。";
    }
    if ([trimmed hasPrefix:@"NOTE: In cases where installd is selected but the stock uninstallation fails"]) {
        return @"注意：如果选择了 installd，但原生卸载失败，TrollStore 会自动回退到使用自定义方法。";
    }

    // 拦截 App 详情弹窗里的长段说明
    if ([trimmed hasPrefix:@"The app runs unsandboxed and can access most of the file system."]) {
        return @"App 以无沙盒模式运行，可访问大部分文件系统。";
    }
    if ([trimmed hasPrefix:@"The app runs sandboxed and can only access the containers listed below."]) {
        return @"App 以沙盒模式运行，只能访问下方列出的容器。";
    }
    if ([trimmed hasPrefix:@"The app can spawn its own embedded binaries with root privileges."]) {
        return @"该 App 可以以 root 权限执行其内置的二进制文件。";
    }
    if ([trimmed hasPrefix:@"The app can spawn arbitrary binaries as the mobile user."]) {
        return @"该 App 可以以 mobile 用户身份执行任意二进制文件。";
    }
    if ([trimmed hasPrefix:@"The app can not spawn other binaries."]) {
        return @"该 App 无法执行其他二进制文件。";
    }

    // 精确处理：iOS 重建图标缓存的长文，涵盖安装了 Persistence Helper 的情况
    if ([trimmed hasPrefix:@"When iOS rebuilds the icon cache"]) {
        if ([trimmed containsString:@"installed into "]) {
            NSRange startRange = [trimmed rangeOfString:@"installed into "];
            NSRange endRange = [trimmed rangeOfString:@" to refresh"];
            if (endRange.location != NSNotFound) {
                NSString *app = [trimmed substringWithRange:NSMakeRange(startRange.location + 15, endRange.location - startRange.location - 15)];
                return [NSString stringWithFormat:@"当 iOS 重建图标缓存时，所有 TrollStore App（包括 TrollStore 本身）都将恢复为“用户”状态，并可能消失或无法启动。如果发生这种情况，您可以使用安装到 %@ 的持久化助手刷新 App 注册，它们将重新正常工作。", app];
            }
        } else if ([trimmed containsString:@"The only way to have persistence"]) {
            return @"当 iOS 重建图标缓存时，所有 TrollStore App（包括 TrollStore 本身）都将恢复为“用户”状态，并可能消失或无法启动。在无根环境中实现持久化的唯一方法是替换一个系统 App，您可以在此选择一个系统 App 来替换为持久化助手，以便在 TrollStore 相关 App 消失或无法启动时刷新它们的注册状态。";
        } else {
            return @"当 iOS 重建图标缓存时，所有 TrollStore App（包括 TrollStore 本身）都将恢复为“用户”状态，并可能消失或无法启动。如果发生这种情况，您可以使用主屏幕上的 TrollHelper App 刷新 App 注册，它们将重新正常工作。";
        }
    }

    // 处理动态拼接的 ldid 状态，如 "ldid: Installed (v2.1.5...)"
    if ([trimmed hasPrefix:@"ldid: Installed"]) {
        return [trimmed stringByReplacingOccurrencesOfString:@"ldid: Installed" withString:@"ldid: 已安装"];
    }
    
    // 处理 Switch to "User" Registration 等
    if ([trimmed hasPrefix:@"Switch to \""] && [trimmed hasSuffix:@"\" Registration"]) {
        NSRange endRange = [trimmed rangeOfString:@"\" Registration"];
        if (endRange.location != NSNotFound) {
            NSString *mid = [trimmed substringWithRange:NSMakeRange(11, endRange.location - 11)];
            return [NSString stringWithFormat:@"切换到“%@”注册", mid];
        }
    }
    
    if ([trimmed hasPrefix:@"Switched '"]) {
        NSRange range = [trimmed rangeOfString:@"' to \"System\" Registration"];
        if (range.location != NSNotFound) {
            NSString *app = [trimmed substringWithRange:NSMakeRange(10, range.location - 10)];
            return [NSString stringWithFormat:@"已将 '%@' 切换为“系统”注册", app];
        }
    }
    if ([trimmed hasPrefix:@"Switching '"]) {
        NSRange range = [trimmed rangeOfString:@"' to \"User\" Registration"];
        if (range.location != NSNotFound) {
            NSString *app = [trimmed substringWithRange:NSMakeRange(11, range.location - 11)];
            return [NSString stringWithFormat:@"正在将 '%@' 切换为“用户”注册", app];
        }
    }
    
    // 处理其他动态拼接状态
    if ([trimmed hasPrefix:@"Helper Installed into "]) return [@"持久化助手安装至 " stringByAppendingString:[trimmed substringFromIndex:21]];
    if ([trimmed hasPrefix:@"Version: "]) return [@"版本: " stringByAppendingString:[trimmed substringFromIndex:9]];
    if ([trimmed hasPrefix:@"Size: "]) return [@"大小: " stringByAppendingString:[trimmed substringFromIndex:6]];
    if ([trimmed hasPrefix:@"Bundle Identifier: "]) return [@"Bundle ID: " stringByAppendingString:[trimmed substringFromIndex:19]];
    
    return str;
}

static void ReplaceInstanceMethod(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

static void ReplaceClassMethod(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    if (!cls) return;
    Method m = class_getClassMethod(cls, sel);
    if (!m) return;
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

static IMP orig_setText = NULL;
static void my_setText(UILabel *self, SEL _cmd, NSString *text) {
    ((void(*)(id, SEL, id))orig_setText)(self, _cmd, T(text));
}
static IMP orig_setAttrText = NULL;
static void my_setAttrText(UILabel *self, SEL _cmd, NSAttributedString *attrText) {
    ((void(*)(id, SEL, id))orig_setAttrText)(self, _cmd, T(attrText));
}
static IMP orig_setTitle = NULL;
static void my_setTitle(UIButton *self, SEL _cmd, NSString *title, UIControlState state) {
    ((void(*)(id, SEL, id, NSUInteger))orig_setTitle)(self, _cmd, T(title), state);
}
static IMP orig_vcSetTitle = NULL;
static void my_vcSetTitle(UIViewController *self, SEL _cmd, NSString *title) {
    ((void(*)(id, SEL, id))orig_vcSetTitle)(self, _cmd, T(title));
}
static IMP orig_navSetTitle = NULL;
static void my_navSetTitle(UINavigationItem *self, SEL _cmd, NSString *title) {
    ((void(*)(id, SEL, id))orig_navSetTitle)(self, _cmd, T(title));
}
static IMP orig_tabSetTitle = NULL;
static void my_tabSetTitle(UITabBarItem *self, SEL _cmd, NSString *title) {
    ((void(*)(id, SEL, id))orig_tabSetTitle)(self, _cmd, T(title));
}
static IMP orig_tabInit = NULL;
static id my_tabInit(UITabBarItem *self, SEL _cmd, NSString *title, UIImage *image, UIImage *selectedImage) {
    return ((id(*)(id, SEL, id, id, id))orig_tabInit)(self, _cmd, T(title), image, selectedImage);
}

static IMP orig_actionImageTitle = NULL;
static id my_actionImageTitle(id self, SEL _cmd, NSString *title, UIImage *image, NSString *ident, id handler) {
    return ((id(*)(id, SEL, id, id, id, id))orig_actionImageTitle)(self, _cmd, T(title), image, ident, handler);
}
static IMP orig_actionTitleStyle = NULL;
static id my_actionTitleStyle(id self, SEL _cmd, NSString *title, NSInteger style, id handler) {
    return ((id(*)(id, SEL, id, NSInteger, id))orig_actionTitleStyle)(self, _cmd, T(title), style, handler);
}

static IMP orig_alertActionWithTitleStyle = NULL;
static id my_alertActionWithTitleStyle(id self, SEL _cmd, NSString *title, NSInteger style, id handler) {
    return ((id(*)(id, SEL, id, NSInteger, id))orig_alertActionWithTitleStyle)(self, _cmd, T(title), style, handler);
}
static IMP orig_alertActionWithTitleImage = NULL;
static id my_alertActionWithTitleImage(id self, SEL _cmd, NSString *title, UIImage *image, NSString *ident, id handler) {
    return ((id(*)(id, SEL, id, id, id, id))orig_alertActionWithTitleImage)(self, _cmd, T(title), image, ident, handler);
}

static IMP orig_alertCtrl = NULL;
static id my_alertCtrl(id self, SEL _cmd, id title, id message, NSInteger style) {
    return ((id(*)(id, SEL, id, id, NSInteger))orig_alertCtrl)(self, _cmd, T(title), T(message), style);
}

static IMP orig_pssProp = NULL;
static id my_pssProp(id self, SEL _cmd, id key) {
    id val = ((id(*)(id, SEL, id))orig_pssProp)(self, _cmd, key);
    if ([key isEqual:@"label"] || [key isEqual:@"footerText"] || [key isEqual:@"title"]) {
        return T(val);
    }
    return val;
}
static IMP orig_pssSetProp = NULL;
static void my_pssSetProp(id self, SEL _cmd, id prop, id key) {
    if ([key isEqual:@"label"] || [key isEqual:@"footerText"] || [key isEqual:@"title"]) {
        ((void(*)(id, SEL, id, id))orig_pssSetProp)(self, _cmd, T(prop), key);
    } else {
        ((void(*)(id, SEL, id, id))orig_pssSetProp)(self, _cmd, prop, key);
    }
}
static IMP orig_pssName = NULL;
static IMP orig_pssSetName = NULL;
static id my_pssName(id self, SEL _cmd) { return T(((id(*)(id, SEL))orig_pssName)(self, _cmd)); }
static void my_pssSetName(id self, SEL _cmd, NSString *name) { ((void(*)(id, SEL, id))orig_pssSetName)(self, _cmd, T(name)); }

static IMP orig_psTitleHeader = NULL;
static id my_psTitleHeader(id self, SEL _cmd, UITableView *tv, NSInteger section) {
    return T(((id(*)(id, SEL, id, NSInteger))orig_psTitleHeader)(self, _cmd, tv, section));
}
static IMP orig_psTitleFooter = NULL;
static id my_psTitleFooter(id self, SEL _cmd, UITableView *tv, NSInteger section) {
    return T(((id(*)(id, SEL, id, NSInteger))orig_psTitleFooter)(self, _cmd, tv, section));
}

static IMP orig_detailedTitle = NULL;
static id my_detailedTitle(id self, SEL _cmd) { return T(((id(*)(id, SEL))orig_detailedTitle)(self, _cmd)); }
static IMP orig_detailedDesc = NULL;
static id my_detailedDesc(id self, SEL _cmd) { return T(((id(*)(id, SEL))orig_detailedDesc)(self, _cmd)); }

__attribute__((constructor))
static void init() {
    loadPlist();
    
    ReplaceInstanceMethod([UILabel class], @selector(setText:), (IMP)my_setText, &orig_setText);
    ReplaceInstanceMethod([UILabel class], @selector(setAttributedText:), (IMP)my_setAttrText, &orig_setAttrText);
    ReplaceInstanceMethod([UIButton class], @selector(setTitle:forState:), (IMP)my_setTitle, &orig_setTitle);
    ReplaceInstanceMethod([UIViewController class], @selector(setTitle:), (IMP)my_vcSetTitle, &orig_vcSetTitle);
    ReplaceInstanceMethod([UINavigationItem class], @selector(setTitle:), (IMP)my_navSetTitle, &orig_navSetTitle);
    
    ReplaceInstanceMethod([UITabBarItem class], @selector(setTitle:), (IMP)my_tabSetTitle, &orig_tabSetTitle);
    ReplaceInstanceMethod([UITabBarItem class], @selector(initWithTitle:image:selectedImage:), (IMP)my_tabInit, &orig_tabInit);
    
    ReplaceClassMethod([UIAction class], @selector(actionWithTitle:image:identifier:handler:), (IMP)my_actionImageTitle, &orig_actionImageTitle);
    ReplaceClassMethod([UIAction class], @selector(actionWithTitle:style:handler:), (IMP)my_actionTitleStyle, &orig_actionTitleStyle);
    
    ReplaceClassMethod([UIAlertAction class], @selector(actionWithTitle:style:handler:), (IMP)my_alertActionWithTitleStyle, &orig_alertActionWithTitleStyle);
    ReplaceClassMethod([UIAlertAction class], @selector(actionWithTitle:image:identifier:handler:), (IMP)my_alertActionWithTitleImage, &orig_alertActionWithTitleImage);
    
    ReplaceClassMethod([UIAlertController class], @selector(alertControllerWithTitle:message:preferredStyle:), (IMP)my_alertCtrl, &orig_alertCtrl);
    
    Class pss = NSClassFromString(@"PSSpecifier");
    ReplaceInstanceMethod(pss, @selector(propertyForKey:), (IMP)my_pssProp, &orig_pssProp);
    ReplaceInstanceMethod(pss, @selector(setProperty:forKey:), (IMP)my_pssSetProp, &orig_pssSetProp);
    ReplaceInstanceMethod(pss, @selector(name), (IMP)my_pssName, &orig_pssName);
    ReplaceInstanceMethod(pss, @selector(setName:), (IMP)my_pssSetName, &orig_pssSetName);
    
    Class psList = NSClassFromString(@"PSListController");
    ReplaceInstanceMethod(psList, @selector(tableView:titleForHeaderInSection:), (IMP)my_psTitleHeader, &orig_psTitleHeader);
    ReplaceInstanceMethod(psList, @selector(tableView:titleForFooterInSection:), (IMP)my_psTitleFooter, &orig_psTitleFooter);
    
    ReplaceInstanceMethod(NSClassFromString(@"TSAppInfo"), @selector(detailedInfoTitle), (IMP)my_detailedTitle, &orig_detailedTitle);
    ReplaceInstanceMethod(NSClassFromString(@"TSAppInfo"), @selector(detailedInfoDescription), (IMP)my_detailedDesc, &orig_detailedDesc);
}
