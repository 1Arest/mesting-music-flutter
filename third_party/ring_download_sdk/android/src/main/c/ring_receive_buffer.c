/* SPDX-License-Identifier: MIT
 * Optional Android RTC receive-buffer adaptation. No packets are read/sent,
 * no original FD is adopted, and no global socket defaults are changed.
 * Java serializes each owner's begin/tune/close; close acknowledges after any
 * admitted synchronous native operation has released all duplicate handles.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <limits.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define RING_BINDINGS 8
#define RING_FD_BOUND 2048
#define RING_REQUEST (1024*1024)
#define RING_SCAN_NS 12000000LL
enum { RING_OK, RING_INVALID, RING_UNAVAILABLE, RING_LIMIT, RING_EXPIRED };
struct ring_binding { int family,port,local; unsigned char address[16]; };
struct ring_match { int fd,ambiguous; uint64_t cookie; };
/* status, matched, adjusted, unmatched, ambiguous, failed, min actual buffer */
struct ring_result { int values[7]; };

static int64_t ring_now(void) {
    struct timespec stamp;
    if(clock_gettime(CLOCK_MONOTONIC,&stamp))return -1;
    return (int64_t)stamp.tv_sec*1000000000LL+stamp.tv_nsec;
}
static int ring_parse(const char *text,int port,struct ring_binding *out) {
    memset(out,0,sizeof(*out));out->port=port;
    if(!text || port<=0 || port>65535 || strlen(text)>INET6_ADDRSTRLEN)return 0;
    if(inet_pton(AF_INET,text,out->address)==1) {
        out->family=AF_INET;
        return out->address[0]!=0 && out->address[0]!=127 && out->address[0]<224 &&
            !(out->address[0]==169 && out->address[1]==254);
    }
    if(inet_pton(AF_INET6,text,out->address)!=1)return 0;
    out->family=AF_INET6;
    struct in6_addr address;memcpy(&address,out->address,sizeof(address));
    return !IN6_IS_ADDR_UNSPECIFIED(&address) && !IN6_IS_ADDR_LOOPBACK(&address) &&
        !IN6_IS_ADDR_LINKLOCAL(&address) && !IN6_IS_ADDR_MULTICAST(&address) &&
        !IN6_IS_ADDR_V4MAPPED(&address);
}
static const void *ring_address(const struct sockaddr *address) {
    if(address->sa_family==AF_INET)return &((const struct sockaddr_in *)address)->sin_addr;
    if(address->sa_family==AF_INET6)return &((const struct sockaddr_in6 *)address)->sin6_addr;
    return NULL;
}
static int ring_local_addresses(struct ring_binding *bindings,size_t count) {
    struct ifaddrs *list=NULL;
    if(getifaddrs(&list))return 0;
    unsigned visited=0;int valid=1;
    for(struct ifaddrs *item=list;item;item=item->ifa_next) {
        if(++visited>128){valid=0;break;}
        if(!item->ifa_addr)continue;
        const void *address=ring_address(item->ifa_addr);
        if(!address)continue;
        for(size_t i=0;i<count;++i)
            if(item->ifa_addr->sa_family==bindings[i].family &&
                    !memcmp(address,bindings[i].address,bindings[i].family==AF_INET?4:16))
                bindings[i].local=1;
    }
    freeifaddrs(list);return valid;
}
static int ring_cookie(int fd,uint64_t *value) {
#ifdef RING_TEST_NO_COOKIE
    (void)fd;(void)value;errno=ENOPROTOOPT;return -1;
#else
    socklen_t length=sizeof(*value);
    if(getsockopt(fd,SOL_SOCKET,SO_COOKIE,value,&length))return -1;
    return length==sizeof(*value) && *value ? 0 : -1;
#endif
}
static int ring_buffer(int fd,int *value) {
    socklen_t length=sizeof(*value);
    if(getsockopt(fd,SOL_SOCKET,SO_RCVBUF,value,&length))return -1;
    return length==sizeof(*value) && *value>0 ? 0 : -1;
}
static int ring_socket_matches(const struct sockaddr_storage *socket,const struct ring_binding *binding) {
    if(socket->ss_family!=binding->family || !binding->local)return 0;
    int port=socket->ss_family==AF_INET ? ntohs(((const struct sockaddr_in *)socket)->sin_port)
        : ntohs(((const struct sockaddr_in6 *)socket)->sin6_port);
    if(port!=binding->port)return 0;
    const void *address=ring_address((const struct sockaddr *)socket);
    unsigned char zero[16]={0};size_t length=binding->family==AF_INET?4:16;
    return !memcmp(address,zero,length) || !memcmp(address,binding->address,length);
}
static void ring_tune(struct ring_binding *bindings,size_t count,int64_t deadline,struct ring_result *result) {
    memset(result,0,sizeof(*result));
    struct ring_match matches[RING_BINDINGS];
    for(size_t i=0;i<RING_BINDINGS;++i){matches[i].fd=-1;matches[i].ambiguous=0;matches[i].cookie=0;}
    DIR *directory=NULL;int duplicate=-1;
    if(!count || count>RING_BINDINGS){result->values[0]=RING_INVALID;return;}
    for(size_t i=0;i<count;++i) {
        bindings[i].local=0;
        if((bindings[i].family!=AF_INET && bindings[i].family!=AF_INET6) ||
                bindings[i].port<=0 || bindings[i].port>65535){result->values[0]=RING_INVALID;return;}
        for(size_t j=0;j<i;++j)
            if(bindings[i].family==bindings[j].family && bindings[i].port==bindings[j].port) {
                result->values[0]=RING_INVALID;return;
            }
    }
    if(ring_now()<0 || ring_now()>=deadline){result->values[0]=RING_EXPIRED;return;}
    if(!ring_local_addresses(bindings,count)){result->values[0]=RING_UNAVAILABLE;return;}
    directory=opendir("/proc/self/fd");
    if(!directory){result->values[0]=RING_UNAVAILABLE;return;}
    unsigned visited=0;
    for(;;) {
        if(ring_now()>=deadline){result->values[0]=RING_EXPIRED;goto done;}
        errno=0;struct dirent *entry=readdir(directory);
        if(!entry){if(errno){result->values[0]=RING_UNAVAILABLE;goto done;}break;}
        if(entry->d_name[0]=='.')continue;
        char *end;errno=0;long fd=strtol(entry->d_name,&end,10);
        if(errno || *end || fd<0 || fd>INT_MAX || ++visited>RING_FD_BOUND) {
            result->values[0]=RING_LIMIT;goto done;
        }
        if(fd==dirfd(directory))continue;
        duplicate=fcntl((int)fd,F_DUPFD_CLOEXEC,0);
        if(duplicate<0){if(errno==EBADF)continue;result->values[0]=RING_UNAVAILABLE;goto done;}
        int flags=fcntl(duplicate,F_GETFL),type=0;socklen_t length=sizeof(type);
        if(flags<0){result->values[0]=RING_UNAVAILABLE;goto done;}
        if(!(flags&O_PATH) && getsockopt(duplicate,SOL_SOCKET,SO_TYPE,&type,&length)) {
            if(errno!=ENOTSOCK){result->values[0]=RING_UNAVAILABLE;goto done;}
            type=0;
        }
        if(type==SOCK_DGRAM) {
            struct sockaddr_storage address;length=sizeof(address);
            if(getsockname(duplicate,(struct sockaddr *)&address,&length)) {
                result->values[0]=RING_UNAVAILABLE;goto done;
            }
            for(size_t i=0;i<count;++i)if(ring_socket_matches(&address,&bindings[i])) {
                uint64_t cookie=0;
                if(ring_cookie(duplicate,&cookie)){result->values[0]=RING_UNAVAILABLE;goto done;}
                if(matches[i].fd<0) {
                    matches[i].fd=duplicate;matches[i].cookie=cookie;duplicate=-1;
                } else if(matches[i].cookie!=cookie)matches[i].ambiguous=1;
                break;
            }
        }
        if(duplicate>=0){int closing=duplicate;duplicate=-1;if(close(closing)){result->values[0]=RING_UNAVAILABLE;goto done;}}
    }
    /* Only after a complete, bounded scan may an unambiguous pinned UDP owner
     * change. Wildcard addresses require an assigned local host candidate. */
    for(size_t i=0;i<count;++i) {
        if(ring_now()>=deadline){result->values[0]=RING_EXPIRED;goto done;}
        struct ring_match *match=&matches[i];
        if(match->fd<0){result->values[3]++;continue;}
        if(match->ambiguous){result->values[4]++;continue;}
        uint64_t cookie=0;int before=0,after=0;
        if(ring_cookie(match->fd,&cookie) || cookie!=match->cookie || ring_buffer(match->fd,&before)) {
            result->values[5]++;continue;
        }
        result->values[1]++;
        int requested=RING_REQUEST;
        if(before<2*RING_REQUEST && setsockopt(match->fd,SOL_SOCKET,SO_RCVBUF,&requested,sizeof(requested))) {
            result->values[5]++;continue;
        }
        if(ring_buffer(match->fd,&after)){result->values[5]++;continue;}
        if(after<before) {
            /* A concurrent kernel cap reduction can defeat a normal increase.
             * Try restoring the Linux-reported previous request, then report
             * failure instead of claiming success or using privileged force. */
            int previous=before/2;
            (void)setsockopt(match->fd,SOL_SOCKET,SO_RCVBUF,&previous,sizeof(previous));
            result->values[5]++;continue;
        }
        if(after>before)result->values[2]++;
        if(!result->values[6] || after<result->values[6])result->values[6]=after;
    }
done:
    if(duplicate>=0 && close(duplicate))result->values[0]=RING_UNAVAILABLE;
    for(size_t i=0;i<count;++i)
        if(matches[i].fd>=0 && close(matches[i].fd))result->values[0]=RING_UNAVAILABLE;
    if(directory && closedir(directory))result->values[0]=RING_UNAVAILABLE;
}

#ifndef RING_RECEIVE_SELFTEST
#include <jni.h>
JNIEXPORT jintArray JNICALL Java_asia_csnas_ringdownload_RingRtcReceiveBuffer_nativeTune(
        JNIEnv *env,jclass type,jobjectArray addresses,jintArray ports) {
    (void)type;struct ring_result result;memset(&result,0,sizeof(result));result.values[0]=RING_INVALID;
    struct ring_binding bindings[RING_BINDINGS];
    if(!addresses || !ports)goto reply;
    jsize count=(*env)->GetArrayLength(env,addresses);
    if(count<1 || count>RING_BINDINGS || (*env)->GetArrayLength(env,ports)!=count)goto reply;
    jint numbers[RING_BINDINGS];(*env)->GetIntArrayRegion(env,ports,0,count,numbers);
    for(jsize i=0;i<count;++i) {
        jstring value=(jstring)(*env)->GetObjectArrayElement(env,addresses,i);
        if(!value)goto reply;
        const char *text=(*env)->GetStringUTFChars(env,value,NULL);
        if(!text){(*env)->DeleteLocalRef(env,value);return NULL;}
        int valid=ring_parse(text,numbers[i],&bindings[i]);
        (*env)->ReleaseStringUTFChars(env,value,text);(*env)->DeleteLocalRef(env,value);
        if(!valid)goto reply;
    }
    int64_t now=ring_now();
    if(now<0){result.values[0]=RING_UNAVAILABLE;goto reply;}
    ring_tune(bindings,(size_t)count,now+RING_SCAN_NS,&result);
reply: {
    jintArray output=(*env)->NewIntArray(env,7);
    if(output)(*env)->SetIntArrayRegion(env,output,0,7,result.values);
    return output;
}
}
#endif
