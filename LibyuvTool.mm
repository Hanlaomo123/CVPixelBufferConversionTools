//
//  LibyuvTool.m
//  CVPixelBufferDemo
//
//  Created by mac on 2020/12/1.
//

#import "LibyuvTool.h"
#import "libyuv.h"
#import <Accelerate/Accelerate.h>

@implementation LibyuvTool

+(CVPixelBufferRef)yuvNV12ToBGRA:(CVPixelBufferRef)pixelBuffer
{
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t pixelWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t pixelHeight = CVPixelBufferGetHeight(pixelBuffer);
    uint8_t *y_frame = (unsigned char *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    uint8_t *uv_frame =(unsigned char *) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    // 创建一个空的32BGRA格式的CVPixelBufferRef
    NSDictionary *pixelAttributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVPixelBufferRef pixelBuffer1 = NULL;
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                        pixelWidth,pixelHeight,kCVPixelFormatType_32BGRA,
                                        (__bridge CFDictionaryRef)pixelAttributes,&pixelBuffer1);
    if (result != kCVReturnSuccess) {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
        return NULL;
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    result = CVPixelBufferLockBaseAddress(pixelBuffer1, 0);
    if (result != kCVReturnSuccess) {
      CFRelease(pixelBuffer1);
      NSLog(@"Failed to lock base address: %d", result);
      return NULL;
    }
    uint8_t *rgb_data = (uint8*)CVPixelBufferGetBaseAddress(pixelBuffer1);
    // 使用libyuv为rgb_data写入数据，将NV12转换为BGRA
    size_t ystride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);//8的倍数，有可能比width宽
    size_t uvstride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    
    size_t bgrastride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer1, 0);
    
    int ret = 0;
    @try {
        ret = libyuv::NV12ToARGB(y_frame, (int)ystride, uv_frame, (int)uvstride, rgb_data, (int)bgrastride/*(int)ystride * 4*/, (int)pixelWidth, (int)pixelHeight);
    } @catch (NSException *exception) {
        ret = libyuv::NV12ToARGB(y_frame, (int)ystride, uv_frame, (int)uvstride, rgb_data, (int)ystride * 4, (int)pixelWidth, (int)pixelHeight);
    } @finally {
        
    }
    if (ret) {
      NSLog(@"Error converting NV12 VideoFrame to BGRA: %d", result);
      CFRelease(pixelBuffer1);
      return NULL;
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer1, 0);

    return pixelBuffer1;
}

+(CVPixelBufferRef)RGBAToNV12:(CVPixelBufferRef)pixelBuffer
{
    //先创建yuv
    CVPixelBufferRef pixelBufferYUV = NULL;
    OSType bufferPixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    size_t width  = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    NSDictionary* optionsDictionary = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, bufferPixelFormat, (__bridge CFDictionaryRef)(optionsDictionary), &pixelBufferYUV);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    uint8_t* argbdata = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t argbstride = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    CVPixelBufferLockBaseAddress(pixelBufferYUV, 0);
    uint8_t* ydata = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBufferYUV, 0);
    size_t ystride = CVPixelBufferGetBytesPerRowOfPlane(pixelBufferYUV, 0);
    size_t uvstride = CVPixelBufferGetBytesPerRowOfPlane(pixelBufferYUV, 1);
    uint8_t* uvdata = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBufferYUV, 1);
    
    libyuv::ARGBToNV12(argbdata, argbstride, ydata, ystride, uvdata, uvstride, width, height);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CVPixelBufferUnlockBaseAddress(pixelBufferYUV, 0);
    return pixelBufferYUV;
}

@end
