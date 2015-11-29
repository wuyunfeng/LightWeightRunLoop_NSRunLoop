//
//  LWNativeLoop.m
//  LightWeightRunLoop
//
//  Created by wuyunfeng on 15/11/28.
//  Copyright © 2015年 com.wuyunfeng.open. All rights reserved.
//

#import "LWNativeLoop.h"
// unix standard
#include <sys/unistd.h>

//SYNOPSIS For Kevent
#include <sys/event.h>
#include <sys/types.h>
#include <sys/time.h>

#include <fcntl.h>


#include <pthread.h>
#include <sys/errno.h>
#define MAX_EVENT_COUNT 16

@implementation LWNativeLoop
{
    int _mReadPipeFd;
    int _mWritePipeFd;
    int _kq;
}

- (instancetype)init
{
    if (self = [super init]) {
        [self nativeInit];
    }
    return self;
}

- (void)nativeRunLoopFor:(NSInteger)timeoutMillis
{
    struct kevent events[MAX_EVENT_COUNT];
    struct timespec *waitTime = NULL;
    if (timeoutMillis == -1) {
        waitTime = NULL;
    } else {
        waitTime = (struct timespec *)malloc(sizeof(struct timespec));
        waitTime->tv_sec = timeoutMillis / 1000;
        waitTime->tv_nsec = timeoutMillis % 1000 * 1000 * 1000;
    }
    int ret = kevent(_kq, NULL, 0, events, MAX_EVENT_COUNT, waitTime);
    NSAssert(ret != -1, @"Failure in kevent().  errno=%d", errno);
    free(waitTime);
    waitTime = NULL; // avoid wild pointer
}

- (void)nativeWakeRunLoop
{
    ssize_t nWrite;
    do {
        nWrite = write(_mWritePipeFd, "w", 1);
    } while (nWrite == -1 && errno == EINTR);
    
    if (nWrite != 1) {
        if (errno != EAGAIN) {
            NSLog(@"Could not write wake signal, errno=%d", errno);
        }
    }
}

- (void)nativeInit
{
    int wakeFds[2];
    
    int result = pipe(wakeFds);
    NSAssert(result == 0, @"Failure in pipe().  errno=%d", errno);
    
    _mReadPipeFd = wakeFds[0];
    _mWritePipeFd = wakeFds[1];
    
    result = fcntl(_mReadPipeFd, F_SETFL, O_NONBLOCK);
    NSAssert(result == 0, @"Failure in fcntl() for read wake fd.  errno=%d", errno);
    
    result = fcntl(_mWritePipeFd, F_SETFL, O_NONBLOCK);
    NSAssert(result == 0, @"Failure in fcntl() for write wake fd.  errno=%d", errno);
    
    _kq = kqueue();
    NSAssert(_kq != -1, @"Failure in kqueue().  errno=%d", errno);
    
    struct kevent changes[1];
    EV_SET(changes, _mReadPipeFd, EVFILT_READ, EV_ADD, 0, 0, NULL);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
    int ret = kevent(_kq, changes, 1, NULL, 0, NULL);
    NSAssert(ret != -1, @"Failure in kevent().  errno=%d", errno);
#pragma clang diagnostic pop
}

- (void)handleReadWake
{
    char buffer[16];
    ssize_t nRead;
    do {
        nRead = read(_mReadPipeFd, buffer, sizeof(buffer));
    } while ((nRead == -1 && errno == EINTR) || nRead == sizeof(buffer));
}

- (void)nativeDestoryKernelFds
{
    close(_kq);
    close(_mReadPipeFd);
    close(_mWritePipeFd);
}

- (void)dealloc
{
    close(_kq);
    close(_mReadPipeFd);
    close(_mWritePipeFd);
}

@end
