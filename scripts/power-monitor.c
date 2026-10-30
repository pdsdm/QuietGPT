#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <unistd.h>
typedef struct IOReportSubscription *IOReportSubscriptionRef;
extern CFMutableDictionaryRef IOReportCopyChannelsInGroup(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef, int32_t);

static double toJoules(int64_t v, CFStringRef unit) {
    char u[16] = {0};
    if (unit) CFStringGetCString(unit, u, sizeof u, kCFStringEncodingUTF8);
    if (!strcmp(u, "mJ")) return v / 1e3;
    if (!strcmp(u, "uJ")) return v / 1e6;
    if (!strcmp(u, "nJ")) return v / 1e9;
    return v;
}

int main(int argc, char **argv) {
    int seconds = argc > 1 ? atoi(argv[1]) : 10;
    CFMutableDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    CFMutableDictionaryRef sub = NULL;
    IOReportSubscriptionRef s = IOReportCreateSubscription(NULL, channels, &sub, 0, NULL);
    CFDictionaryRef prev = IOReportCreateSamples(s, sub, NULL);
    for (int t = 0; t < seconds * 2; t++) {
        usleep(500000);
        CFDictionaryRef cur = IOReportCreateSamples(s, sub, NULL);
        CFDictionaryRef delta = IOReportCreateSamplesDelta(prev, cur, NULL);
        CFArrayRef items = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
        double cpu = 0, gpu = 0, ane = 0;
        for (CFIndex i = 0; i < CFArrayGetCount(items); i++) {
            CFDictionaryRef item = CFArrayGetValueAtIndex(items, i);
            char name[128] = {0};
            CFStringGetCString(IOReportChannelGetChannelName(item), name, sizeof name, kCFStringEncodingUTF8);
            double j = toJoules(IOReportSimpleGetIntegerValue(item, 0), IOReportChannelGetUnitLabel(item));
            if (strstr(name, "ANE")) ane += j;
            else if (!strcmp(name, "GPU Energy")) gpu += j;
            else if (strstr(name, "CPU Energy")) cpu += j;
        }
        printf("t=%4.1fs  CPU %6.2f W  GPU %6.2f W  ANE %6.2f W\n", (t + 1) / 2.0, cpu * 2, gpu * 2, ane * 2);
        fflush(stdout);
        CFRelease(prev); CFRelease(delta);
        prev = cur;
    }
    return 0;
}
