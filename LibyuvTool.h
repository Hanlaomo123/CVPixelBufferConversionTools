//
//  LibyuvTool.h
//  CVPixelBufferDemo
//
//  Created by mac on 2020/12/1.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@interface LibyuvTool : NSObject

+(CVPixelBufferRef)yuvNV12ToBGRA:(CVPixelBufferRef)pixelBuffer;

+(CVPixelBufferRef)RGBAToNV12:(CVPixelBufferRef)pixelBuffer;
@end

NS_ASSUME_NONNULL_END
