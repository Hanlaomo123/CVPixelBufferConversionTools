//
//  CVPixelBufferConversionTools.h
//
//  Created by hanlaomo on 2020/12/1.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 视频帧格式
typedef NS_ENUM(NSInteger, CVPixelBufferFormatEnum) {
    RGBA = 3,
    NV21 = 1,
    BGRA = 0,
    RGB = 2,
    NV12 = 4,
    I420 = 5
};

@interface CVPixelBufferConversionTools : NSObject

///*
/// 合并pixbuffer和UIImage，将UIImage覆盖到basePixelBuffer，起始位置为aPoint
///*/
+ (void)addImage:(UIImage*)image toBasePixBuffer:(CVPixelBufferRef)basePixelBuffer atPosition:(CGPoint)aPoint;

///*
/// 合并pixbuffer，将pixelBuffer覆盖到basePixelBuffer上，aPoint为起始位置
///*/
+(void)addPixBuffer:(CVPixelBufferRef)pixelBuffer toBasePixBuffer:(CVPixelBufferRef)basePixelBuffer atPosition:(CGPoint)aPoint;

///*
/// 创建所需尺寸的新pixBuffer，使用旧buffer数据填充，空余部分补黑
/// params：pixelBuffer旧pixbuffer数据
///         nSize新buffer尺寸
///         cRect裁剪旧buffer的位置和尺寸
///         aPoint裁剪部分在新buffer的位置
///*/
+(CVPixelBufferRef)reSizePixBuffer:(CVPixelBufferRef)pixelBuffer withSize:(CGSize)nSize clipRect:(CGRect)cRect atPosition:(CGPoint)aPoint;

+(void)memcopyPixBuffer:(CVPixelBufferRef)pixelBuffer toBasePixBuffer:(CVPixelBufferRef)basePixelBuffer;

@end

NS_ASSUME_NONNULL_END
