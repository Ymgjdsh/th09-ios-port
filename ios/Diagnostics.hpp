#pragma once
#include <sys/utsname.h>

// Local, bounded diagnostic logs. No save data, resource contents or identifiers
// are collected; exporting only creates a file for the system share sheet.
namespace TH09Diagnostics {
static constexpr NSUInteger limit=1024*1024;
static FILE* file=nullptr;
static NSString* currentPath;
static NSString* previousPath;

static NSString* sanitized(NSString* value){
    if(!value)return @"";
    NSMutableString* text=[value mutableCopy];
    for(NSString* path in @[NSHomeDirectory(),NSBundle.mainBundle.bundlePath]){
        if(path.length){
            [text replaceOccurrencesOfString:[@"/private" stringByAppendingString:path] withString:@"[app path]" options:0 range:NSMakeRange(0,text.length)];
            [text replaceOccurrencesOfString:path withString:@"[app path]" options:0 range:NSMakeRange(0,text.length)];
        }
    }
    // Error strings can quote file URLs or contain paths with spaces. For an
    // unknown absolute path, redact the rest of that quoted field / log line
    // rather than leave a username or directory suffix after the first space.
    NSRegularExpression* paths=[NSRegularExpression regularExpressionWithPattern:@"(?:file://)?/(?:private/)?(?:var|Users|Volumes|Applications|tmp|opt|home)/[^\\r\\n\\\"'<>]*" options:0 error:nullptr];
    NSString* result=[paths stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0,text.length) withTemplate:@"[private path]"];
    return result?:@"[Diagnostic text unavailable]";
}
static NSData* tail(NSString* path,NSUInteger maximum){
    if(!path.length)return nil;
    FILE* source=std::fopen(path.fileSystemRepresentation,"rb");if(!source)return nil;
    if(std::fseek(source,0,SEEK_END)!=0){std::fclose(source);return nil;}
    const long length=std::ftell(source);if(length<0){std::fclose(source);return nil;}
    const NSUInteger count=MIN((NSUInteger)length,maximum);
    if(std::fseek(source,length-(long)count,SEEK_SET)!=0){std::fclose(source);return nil;}
    NSMutableData* data=[NSMutableData dataWithLength:count];const size_t read=std::fread(data.mutableBytes,1,count,source);std::fclose(source);data.length=read;
    // Start at a full line after truncating, including a complete UTF-8 character.
    if((NSUInteger)length>count){
        const auto* bytes=(const unsigned char*)data.bytes;NSUInteger first=0;
        while(first<data.length&&bytes[first]!='\n')++first;
        if(first<data.length)data=[[data subdataWithRange:NSMakeRange(first+1,data.length-first-1)]mutableCopy];
    }
    return data;
}
static NSString* logText(NSString* path){
    NSData* data=tail(path,limit);if(!data)return @"(No log available.)\n";
    NSString* text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    if(!text)text=[[NSString alloc]initWithData:data encoding:NSISOLatin1StringEncoding];
    return sanitized(text);
}
static void begin(NSString* documents){
    currentPath=[documents stringByAppendingPathComponent:@"startup.log"];
    previousPath=[documents stringByAppendingPathComponent:@"previous-startup.log"];
    NSData* previous=tail(currentPath,limit);
    if(previous)[previous writeToFile:previousPath options:NSDataWritingAtomic error:nullptr];
    file=std::fopen(currentPath.fileSystemRepresentation,"w");
}
static void write(const char* message){
    NSString* safe=sanitized([NSString stringWithUTF8String:message?message:""]);
    if(safe.length>8192)safe=[[safe substringToIndex:8192]stringByAppendingString:@" [message truncated]"];
    NSLog(@"[TH09] %@",safe);
    if(!file)return;
    NSData* line=[[NSString stringWithFormat:@"%.3f %@\n",SDL_GetTicks()/1000.,safe]dataUsingEncoding:NSUTF8StringEncoding];
    const long length=std::ftell(file);
    if(length>=0&&(NSUInteger)length+line.length>limit){
        std::fflush(file);std::fclose(file);file=nullptr;
        NSData* recent=tail(currentPath,limit/2);
        file=std::fopen(currentPath.fileSystemRepresentation,"w");if(!file)return;
        std::fputs("[Earlier lines omitted: log size limit.]\n",file);
        if(recent.length)std::fwrite(recent.bytes,1,recent.length,file);
    }
    std::fwrite(line.bytes,1,line.length,file);std::fflush(file);
}
static NSURL* exportLog(NSString* runtime,NSError** error){
    if(file)std::fflush(file);
    NSString* documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString* folder=[documents stringByAppendingPathComponent:@"Logs"];
    if(![[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:error])return nil;
    NSDate* now=NSDate.date;NSDateFormatter* formatter=[[NSDateFormatter alloc]init];formatter.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];formatter.dateFormat=@"yyyyMMdd-HHmmss-SSS";
    NSString* stem=[NSString stringWithFormat:@"TH09-diagnostics-%@",[formatter stringFromDate:now]];
    NSString* name=[stem stringByAppendingPathExtension:@"txt"];
    for(unsigned suffix=1;[[NSFileManager defaultManager]fileExistsAtPath:[folder stringByAppendingPathComponent:name]];++suffix)name=[[NSString stringWithFormat:@"%@-%u",stem,suffix]stringByAppendingPathExtension:@"txt"];
    struct utsname machine{};const bool machineOK=uname(&machine)==0;
    NSBundle* bundle=NSBundle.mainBundle;UIDevice* device=UIDevice.currentDevice;
    NSMutableString* report=[NSMutableString stringWithFormat:@"TH09 诊断日志 / Diagnostic Log\nCreated (UTC): %@\nDevice model: %@ (%s)\nSystem: %@ %@\nApp: %@\nVersion: %@\nBuild: %@\nFlavor: %@\nTH09SourceFingerprint: %@\nGame: Japanese 1.50a / Offline / iOS 14+\n\n",[formatter stringFromDate:now],device.model,machineOK?machine.machine:"unknown",device.systemName,device.systemVersion,[bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]?:@"TH09",[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"unknown",[bundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"unknown",[bundle objectForInfoDictionaryKey:@"TH09BuildFlavor"]?:@"game",[bundle objectForInfoDictionaryKey:@"TH09SourceFingerprint"]?:@"unknown"];
    [report appendString:sanitized(runtime)];
    [report appendString:@"\n--- Current launch: startup.log (up to 1 MiB) ---\n"];[report appendString:logText(currentPath)];
    [report appendString:@"\n--- Previous launch: previous-startup.log (up to 1 MiB) ---\n"];[report appendString:logText(previousPath)];
    NSURL* url=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];
    return [report writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error]?url:nil;
}
}
