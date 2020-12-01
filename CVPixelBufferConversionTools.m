//
//  CVPixelBufferConversionTools.m
//  T-Video
//
//  Created by mac on 2020/12/1.
//
#import <UIKit/UIKit.h>
#import "CVPixelBufferConversionTools.h"
#import "LibyuvTool.h"

@implementation CVPixelBufferConversionTools

+(int)clamp:(double)val{
    if (val < 0) {
        return 0;
    }
    if (val > 255) {
        return 255;
    }
    return (int)round(val);
}
///*
/// 合并pixbuffer和UIImage，将UIImage覆盖到basePixelBuffer，起始位置为aPoint
///*/
+ (void)addImage:(UIImage*)image toBasePixBuffer:(CVPixelBufferRef)basePixelBuffer atPosition:(CGPoint)aPoint{
    CVPixelBufferFormatEnum format;
    OSType formatType = CVPixelBufferGetPixelFormatType(basePixelBuffer);
    switch (formatType) {
        case kCVPixelFormatType_32BGRA:
            format = BGRA;
            break;
        case kCVPixelFormatType_32RGBA:
            format = RGBA;
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            format = NV12;
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            format = NV12;
            break;
        default:
            format = -1;
            break;
    }
    assert(format == NV12 || format == BGRA || format == RGBA);
    
    CGImageRef imageRef = [image CGImage];
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageRef);
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    size_t pixelCount = width * height;
    
    CGColorSpaceRef colorRef = CGColorSpaceCreateDeviceRGB();
    // Get source image data
    unsigned char *data = (uint8_t *) malloc(pixelCount * 4);
    CGContextRef imageContext = CGBitmapContextCreate(data,
            width, height,
            8, width * 4,
            colorRef, alphaInfo);
    CGContextDrawImage(imageContext, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(imageContext);
    CGColorSpaceRelease(colorRef);
    
    

    size_t offset,p;
    int r, g, b,a, Y, U, V;
    uint8_t *y_tmp = NULL;
    uint8_t *uv_tmp = NULL;
    uint8_t *rgba_tmp = NULL;

    if (format == NV12) {
        y_tmp = malloc(pixelCount);
        memset(y_tmp, 0x80, pixelCount);
        uv_tmp = malloc(pixelCount/2);
        memset(uv_tmp, 0x80, pixelCount/2);
    }else if (format == BGRA || format == RGBA){
        //先将被覆盖区域像素数据存起来，blend之后再覆盖原数据。
        rgba_tmp = malloc(pixelCount * 4);
        memset(rgba_tmp, 0x80, pixelCount * 4);
    }
    
    //填充起始位置
    size_t fillStartX = aPoint.x;
    size_t fillStartY = aPoint.y;
    fillStartX = fillStartX & 0xFFFE;
    fillStartY = fillStartY & 0xFFFE;

    //原始尺寸
    size_t basePixWidth = CVPixelBufferGetWidth(basePixelBuffer);
    size_t basePixHeight = CVPixelBufferGetHeight(basePixelBuffer);

    //真实需裁减的尺寸,防止超出区域
    size_t clipW = MIN(width, basePixWidth - fillStartX);
    size_t clipH = MIN(height, basePixHeight - fillStartY);

    //Y通道数据大小
    size_t yClipH = clipH;
    size_t yClipW = clipW;
    //uv通道数据大小
    size_t uvClipH = clipH / 2;
    size_t uvClipW = clipW;
    
    CVPixelBufferLockBaseAddress(basePixelBuffer, 0);
    
    size_t bpr0 = CVPixelBufferGetBytesPerRowOfPlane(basePixelBuffer, 0);
    size_t bpr1 = CVPixelBufferGetBytesPerRowOfPlane(basePixelBuffer, 1);
    //先获取被覆盖区域的图像数据，用来做透明度混合
    if (format == NV12) {
        //y
        uint8_t *yPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 0);
        for (int row = 0; row < yClipH; row++) {
            size_t oH = fillStartY + row;
            size_t srcPos = fillStartX + bpr0 * oH;
            memcpy(y_tmp + yClipW * row, yPlane + srcPos, yClipW);
        }
        //uv
        uint8_t *uvPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 1);
        for (int row = 0; row < uvClipH; row++) {
            size_t oH = fillStartY / 2 + row;
            size_t srcPos =  fillStartX + bpr1 * oH;
            memcpy(uv_tmp + row * uvClipW, uvPlane + srcPos , uvClipW);
        }
    }else if (format == BGRA || format == RGBA) {
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddress(basePixelBuffer);
        size_t bytePerRow = CVPixelBufferGetBytesPerRow(basePixelBuffer);
        for (size_t i = 0; i < clipH; i++) {
            size_t oH = fillStartY + i;
            size_t srcPos = bytePerRow * oH + fillStartX * 4;
            size_t desPos = clipW * i * 4;
            memcpy(rgba_tmp + desPos, rgba_frame + srcPos, clipW * 4);
        }
    }
    
    /**
        rgba图层混合算法公式如下：
        C12 = (C1A1(1-A2)+C2A2)/(A1+A2-A1*A2)
        取值范围都是 0 ~ 1
     */

    for (int row = 0; row < clipH; row++) {
        for (int col = 0; col < clipW; col++) {
            offset = ((clipW * row) + col);
            p = offset * 4;
            r = g = b = a = 0;
            //图片RGBA
            size_t image_p = (width * row + col) * 4;
            if (alphaInfo == kCGImageAlphaPremultipliedLast || alphaInfo == kCGImageAlphaLast) {
                r = data[image_p + 0];
                g = data[image_p + 1];
                b = data[image_p + 2];
                a = data[image_p + 3];
            }else if (alphaInfo == kCGImageAlphaPremultipliedFirst || alphaInfo == kCGImageAlphaFirst){
                a = data[image_p + 0];
                r = data[image_p + 1];
                g = data[image_p + 2];
                b = data[image_p + 3];
            }else if (alphaInfo == kCGImageAlphaNoneSkipLast){
                r = data[image_p + 0];
                g = data[image_p + 1];
                b = data[image_p + 2];
                a = 255;
            }else if (alphaInfo == kCGImageAlphaNoneSkipFirst){
                a = 255;
                r = data[image_p + 1];
                g = data[image_p + 2];
                b = data[image_p + 3];
            }
            
            if (format == BGRA || format == RGBA) {
                //底层rgb
                double r0 = 0;
                double g0 = 0;
                double b0 = 0;
                double a0 = 0;
                if (format == BGRA){
                    b0 = rgba_tmp[p + 0] / 255.0;
                    g0 = rgba_tmp[p + 1] / 255.0;
                    r0 = rgba_tmp[p + 2] / 255.0;
                    a0 = rgba_tmp[p + 3] / 255.0;
                }else if (format == RGBA){
                    r0 = rgba_tmp[p + 0] / 255.0;
                    g0 = rgba_tmp[p + 1] / 255.0;
                    b0 = rgba_tmp[p + 2] / 255.0;
                    a0 = rgba_tmp[p + 3] / 255.0;
                }
                //图层混合blend
                double r1 = r / 255.0;
                double g1 = g / 255.0;
                double b1 = b / 255.0;
                double a1 = a / 255.0;
                //如果图片像素alpha==0，不必blend运算，直接使用底层像素rgba
                if (a == 0) {
                    r = r0 * 255;
                    g = g0 * 255;
                    b = b0 * 255;
                    a = a0 * 255;
                }else{
                    r = [self.class clamp:(r0 * a0 * (1 - a1) + r1 * a1) / (a0 + a1 - a0 * a1) * 255];
                    g = [self.class clamp:(g0 * a0 * (1 - a1) + g1 * a1) / (a0 + a1 - a0 * a1) * 255];
                    b = [self.class clamp:(b0 * a0 * (1 - a1) + b1 * a1) / (a0 + a1 - a0 * a1) * 255];
                    a = [self.class clamp:(a0 + a1 - a0 * a1) * 255];
                }
                
                if (format == BGRA) {
                    rgba_tmp[p+0] = b;
                    rgba_tmp[p+1] = g;
                    rgba_tmp[p+2] = r;
                    rgba_tmp[p+3] = a;
                }else if (format == RGBA) {
                    rgba_tmp[p+0] = r;
                    rgba_tmp[p+1] = g;
                    rgba_tmp[p+2] = b;
                    rgba_tmp[p+3] = a;
                }
            }
            
            if (format == NV12) {
                //底层被覆盖像素区域YUV
                size_t y_pos = offset;
                size_t uv_pos = row/2*clipW + (int)(col/2)*2;
                Y = y_tmp[y_pos];
                U = uv_tmp[uv_pos];
                V = uv_tmp[uv_pos + 1];
                
                int yuv_r = (298*Y + 411 * V - 57344)>>8;
                int yuv_g = (298*Y - 101* U - 211* V+ 34739)>>8;
                int yuv_b = (298*Y + 519* U- 71117)>>8;
                int yuv_a = 255;
                
                double r0 = yuv_r / 255.0;
                double g0 = yuv_g / 255.0;
                double b0 = yuv_b / 255.0;
                double a0 = yuv_a / 255.0;
                
                //图层混合blend
                double r1 = r / 255.0;
                double g1 = g / 255.0;
                double b1 = b / 255.0;
                double a1 = a / 255.0;
                if (a == 0) {
                    r = yuv_r;
                    g = yuv_g;
                    b = yuv_b;
                    a = yuv_a;
                }else{
                    r = [self.class clamp:(r0 * a0 * (1 - a1) + r1 * a1) / (a0 + a1 - a0 * a1) * 255];
                    g = [self.class clamp:(g0 * a0 * (1 - a1) + g1 * a1) / (a0 + a1 - a0 * a1) * 255];
                    b = [self.class clamp:(b0 * a0 * (1 - a1) + b1 * a1) / (a0 + a1 - a0 * a1) * 255];
                    a = [self.class clamp:(a0 + a1 - a0 * a1) * 255];
                }
                
                //转YUV公式
                Y = 0.299 * r + 0.587 * g + 0.114 * b;
                U = -0.1687 * r - 0.3313 * g + 0.5 * b + 128;
                V = 0.5 * r - 0.4187 * g - 0.0813 * b + 128;
                
                y_tmp[y_pos] = Y;
                if((row&1)||(col&1)) continue;
                uv_tmp[uv_pos] = U;
                uv_tmp[uv_pos + 1] = V;
            }
        }
    }
    free(data);

    
    if (format == NV12) {
        //填充Y通道数据
        uint8_t *yPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 0);
        for (int row = 0; row < yClipH; row++) {
            size_t oH = fillStartY + row;
            size_t desPos = fillStartX + bpr0 * oH;
            memcpy(yPlane + desPos, y_tmp + row * yClipW, yClipW);
        }
        //填充UV通道数据
        uint8_t *uvPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 1);
        for (int row = 0; row < uvClipH; row++) {
            size_t oH = fillStartY / 2 + row;
            size_t desPos =  fillStartX + bpr1 * oH;
            memcpy(uvPlane + desPos, uv_tmp + row * uvClipW, uvClipW);
        }
    }else if (format == BGRA || format == RGBA){
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddress(basePixelBuffer);
        size_t bytePerRow = CVPixelBufferGetBytesPerRow(basePixelBuffer);
        for (size_t i = 0; i < clipH; i++) {
            size_t oH = fillStartY + i;
            size_t srcPos = clipW * i * 4;
            size_t desPos = bytePerRow * oH + fillStartX * 4;
            memcpy(rgba_frame + desPos, rgba_tmp + srcPos, clipW * 4);
        }
    }
    if (format == NV12) {
        free(y_tmp);
        free(uv_tmp);
    }else if (format == BGRA || format == RGBA){
        free(rgba_tmp);
    }
    
    CVPixelBufferUnlockBaseAddress(basePixelBuffer, 0);
}

///*
/// 合并pixbuffer，将pixelBuffer覆盖到basePixelBuffer上，aPoint为起始位置
///*/
+(void)addPixBuffer:(CVPixelBufferRef)pixelBuffer toBasePixBuffer:(CVPixelBufferRef)basePixelBuffer atPosition:(CGPoint)aPoint{

    CVPixelBufferFormatEnum format;
    OSType formatType = CVPixelBufferGetPixelFormatType(basePixelBuffer);
    switch (formatType) {
        case kCVPixelFormatType_32BGRA:
            format = BGRA;
            if (CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                CVPixelBufferRef tmp = [LibyuvTool yuvNV12ToBGRA:pixelBuffer];
                CVPixelBufferRelease(pixelBuffer);
                pixelBuffer = tmp;
            }
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            format = NV12;
            if (CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA) {
                CVPixelBufferRef tmp = [LibyuvTool RGBAToNV12:pixelBuffer];
                CVPixelBufferRelease(pixelBuffer);
                pixelBuffer = tmp;
            }
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            format = NV12;
            if (CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA) {
                CVPixelBufferRef tmp = [LibyuvTool RGBAToNV12:pixelBuffer];
                CVPixelBufferRelease(pixelBuffer);
                pixelBuffer = tmp;
            }
            break;
        default:
            format = BGRA;
            break;
    }
    assert(format == NV12 || format == BGRA);
    
    //原始尺寸
    size_t basePixWidth = CVPixelBufferGetWidth(basePixelBuffer);
    size_t basePixHeight = CVPixelBufferGetHeight(basePixelBuffer);
    //原始尺寸
    size_t pixWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t pixHeight = CVPixelBufferGetHeight(pixelBuffer);
    //裁剪起始位置
    size_t startX = 0;
    size_t startY = 0;
    startX = startX & 0xFFFE;
    startY = startY & 0xFFFE;
    //填充起始位置
    size_t fillStartX = aPoint.x;
    size_t fillStartY = aPoint.y;
    fillStartX = fillStartX & 0xFFFE;
    fillStartY = fillStartY & 0xFFFE;
    //真实需裁减的尺寸,防止超出区域
    size_t clipW = MIN(pixWidth, basePixWidth - fillStartX);
    size_t clipH = MIN(pixHeight, basePixHeight - fillStartY);
    
    size_t clipSize = clipH * clipW;
    size_t clipFrameLength = clipH * clipW * 3 / 2;
    
    size_t bytePerRow = 0;
    size_t rows = 0;
    if (format == BGRA) {
        bytePerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        rows = CVPixelBufferGetHeight(pixelBuffer);
        clipFrameLength = bytePerRow * rows;
    }
    
    uint8_t *frame_tmp = malloc(clipFrameLength);
    memset(frame_tmp, 0x80, clipFrameLength);
    
    //先拷贝需要的数据
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    //Y通道数据大小
    size_t yClipH = clipH;
    size_t yClipW = clipW;
    //uv通道数据大小
    size_t uvClipH = clipH / 2;
    size_t uvClipW = clipW;
    
    if (format == NV12) {
        //获取CVImageBufferRef中的y数据
        uint8_t *y_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        //获取CMVImageBufferRef中的uv数据
        uint8_t *uv_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        
        size_t ori_bpr0 = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        size_t ori_bpr1 = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        
        //提取Y数据
        for (size_t i = 0; i < yClipH; i++) {
            size_t oH = startY + i;
            size_t srcPos = startX + ori_bpr0 * oH;
            memcpy(frame_tmp+yClipW * i, y_frame+srcPos, yClipW);
        }
        
        //提取UV数据
        for (size_t i = 0; i < uvClipH; i++) {
            size_t oH = startY / 2 + i;
            size_t srcPos =  startX + ori_bpr1 * oH;
            size_t desPos = clipSize + uvClipW * i;
            memcpy(frame_tmp+desPos, uv_frame+srcPos, uvClipW);
        }
    }else if (format == BGRA) {
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddress(pixelBuffer);
        for (size_t i = 0; i < clipH; i++) {
            size_t oH = startY + i;
            size_t srcPos = bytePerRow * oH + startX * 4;
            size_t desPos = clipW * 4 * i;
            memcpy(frame_tmp + desPos, rgba_frame + srcPos, clipW * 4);
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    
    CVPixelBufferLockBaseAddress(basePixelBuffer, 0);
    if (format == NV12) {
        size_t bpr0 = CVPixelBufferGetBytesPerRowOfPlane(basePixelBuffer, 0);
        size_t bpr1 = CVPixelBufferGetBytesPerRowOfPlane(basePixelBuffer, 1);
        //填充Y通道数据
        uint8_t *yPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 0);
        for (int row = 0; row < yClipH; row++) {
            size_t oH = fillStartY + row;
            size_t desPos = fillStartX + bpr0 * oH;
            memcpy(yPlane + desPos, frame_tmp + row * yClipW, yClipW);
        }
        //填充UV通道数据
        uint8_t *uvPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 1);
        for (int row = 0; row < uvClipH; row++) {
            size_t oH = fillStartY / 2 + row;
            size_t desPos =  fillStartX + bpr1 * oH;
            memcpy(uvPlane + desPos, frame_tmp + yClipW * yClipH + row * uvClipW, uvClipW);
        }
    }else if (format == BGRA) {
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddress(basePixelBuffer);
        size_t bytesRGB = CVPixelBufferGetBytesPerRow(basePixelBuffer);
        for (size_t i = 0; i < clipH; i++) {
            size_t oH = fillStartY + i;
            size_t srcPos = clipW * 4 * i;
            size_t desPos = bytesRGB * oH + fillStartX * 4;
            memcpy(rgba_frame + desPos, frame_tmp + srcPos, clipW * 4);
        }
    }
    
    CVPixelBufferUnlockBaseAddress(basePixelBuffer, 0);
    free(frame_tmp);
    CVPixelBufferRelease(pixelBuffer);
}


///*
/// 创建所需尺寸的新pixBuffer，使用旧buffer数据填充，空余部分补黑
/// params：pixelBuffer旧pixbuffer数据
///         nSize新buffer尺寸
///         cRect裁剪旧buffer的位置和尺寸
///         aPoint裁剪部分在新buffer的位置
///*/
+(CVPixelBufferRef)reSizePixBuffer:(CVPixelBufferRef)pixelBuffer withSize:(CGSize)nSize clipRect:(CGRect)cRect atPosition:(CGPoint)aPoint{
    CVPixelBufferFormatEnum format;
    OSType formatType = CVPixelBufferGetPixelFormatType(pixelBuffer);
    switch (formatType) {
        case kCVPixelFormatType_32BGRA:
            format = BGRA;
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            format = NV12;
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            format = NV12;
            break;
        default:
            format = BGRA;
            break;
    }
    assert(format == NV12 || format == BGRA);
    //原始尺寸
    size_t pixWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t pixHeight = CVPixelBufferGetHeight(pixelBuffer);
    //裁剪起始位置
    size_t startX = cRect.origin.x;
    size_t startY = cRect.origin.y;
    startX = startX & 0xFFFE;
    startY = startY & 0xFFFE;
    //真实需裁减的尺寸,防止超出区域
    size_t clipW = MIN(cRect.size.width, pixWidth - cRect.origin.x);
    clipW = MIN(clipW, nSize.width - aPoint.x);
    size_t clipH = MIN(cRect.size.height, pixHeight - cRect.origin.y);
    clipH = MIN(clipH, nSize.height - aPoint.y);
    
    size_t clipSize = clipH * clipW;
    size_t clipFrameLength = clipH * clipW * 3 / 2;
    
    //填充起始位置
    size_t fillStartX = aPoint.x;
    size_t fillStartY = aPoint.y;
    fillStartX = fillStartX & 0xFFFE;
    fillStartY = fillStartY & 0xFFFE;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t bytePerRow = 0;
    size_t rows = 0;
    if (format == BGRA) {
        bytePerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        rows = CVPixelBufferGetHeight(pixelBuffer);
        clipFrameLength = bytePerRow * rows;
    }
    uint8_t *frame_tmp = malloc(clipFrameLength);
    memset(frame_tmp, 0x80, clipFrameLength);
    
    //Y通道数据大小
    size_t yClipH = clipH;
    size_t yClipW = clipW;
    //uv通道数据大小
    size_t uvClipH = clipH / 2;
    size_t uvClipW = clipW;
    
    //copy所需数据
    if (format == NV12) {
        //获取CVImageBufferRef中的y数据
        uint8_t *y_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        //获取CMVImageBufferRef中的uv数据
        uint8_t *uv_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        
        size_t ori_bpr0 = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        size_t ori_bpr1 = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        
        //提取Y数据
        for (size_t i = 0; i < yClipH; i++) {
            size_t oH = startY + i;
            size_t srcPos = startX + ori_bpr0 * oH;
            memcpy(frame_tmp+yClipW * i, y_frame+srcPos, yClipW);
        }
        
        //提取UV数据
        for (size_t i = 0; i < uvClipH; i++) {
            size_t oH = startY / 2 + i;
            size_t srcPos =  startX + ori_bpr1 * oH;
            size_t desPos = clipSize + uvClipW * i;
            memcpy(frame_tmp+desPos, uv_frame+srcPos, uvClipW);
        }
    }else if (format == BGRA){
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddress(pixelBuffer);
        for (size_t i = 0; i < yClipH; i++) {
            size_t oH = startY + i;
            size_t srcPos = bytePerRow * oH + startX * 4;
            size_t desPos = clipW * i * 4;
            memcpy(frame_tmp + desPos, rgba_frame + srcPos, clipW * 4);
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    //创建新PixelBuffer
    NSDictionary *options = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVPixelBufferRef re = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, nSize.width, nSize.height, formatType, (__bridge CFDictionaryRef)(options), &re);
    NSParameterAssert(status == kCVReturnSuccess && re != NULL);
    
    //数据填充
    CVPixelBufferLockBaseAddress(re, 0);
    if (format == NV12) {
        size_t height0 = CVPixelBufferGetHeightOfPlane(re, 0);
        size_t bpr0 = CVPixelBufferGetBytesPerRowOfPlane(re, 0);
        size_t height1 = CVPixelBufferGetHeightOfPlane(re, 1);
        size_t bpr1 = CVPixelBufferGetBytesPerRowOfPlane(re, 1);
        //填充Y通道数据
        uint8_t *yPlane = CVPixelBufferGetBaseAddressOfPlane(re, 0);
        memset(yPlane, 0x80, bpr0 * height0);
        for (int row = 0; row < yClipH; row++) {
            size_t oH = fillStartY + row;
            size_t desPos = fillStartX + bpr0 * oH;
            memcpy(yPlane + desPos, frame_tmp + row * yClipW, yClipW);
        }
        //填充UV通道数据
        uint8_t *uvPlane = CVPixelBufferGetBaseAddressOfPlane(re, 1);
        memset(uvPlane, 0x80, height1 * bpr1);
        for (int row = 0; row < uvClipH; row++) {
            size_t oH = fillStartY / 2 + row;
            size_t desPos =  fillStartX + bpr1 * oH;
            memcpy(uvPlane + desPos, frame_tmp + yClipW * yClipH + row * uvClipW, uvClipW);
        }
    }else if (format == BGRA){
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddress(re);
        size_t bytesRGB = CVPixelBufferGetBytesPerRow(re);
        for (size_t i = 0; i < clipH; i++) {
            size_t oH = fillStartY + i;
            size_t srcPos = clipW * i * 4;
            size_t desPos = bytesRGB * oH + fillStartX * 4;
            memcpy(rgba_frame + desPos, frame_tmp + srcPos, clipW * 4);
        }
    }
    
    CVPixelBufferUnlockBaseAddress(re, 0);
    free(frame_tmp);
    return re;
}

+(void)memcopyPixBuffer:(CVPixelBufferRef)pixelBuffer toBasePixBuffer:(CVPixelBufferRef)basePixelBuffer{
    CVPixelBufferFormatEnum format;
    OSType formatType = CVPixelBufferGetPixelFormatType(basePixelBuffer);
    switch (formatType) {
        case kCVPixelFormatType_32BGRA:
            format = BGRA;
            if (CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                pixelBuffer = [LibyuvTool yuvNV12ToBGRA:pixelBuffer];
            }
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            format = NV12;
            if (CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA) {
                pixelBuffer = [LibyuvTool RGBAToNV12:pixelBuffer];
            }
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            format = NV12;
            if (CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA) {
                pixelBuffer = [LibyuvTool RGBAToNV12:pixelBuffer];
            }
            break;
        default:
            format = BGRA;
            break;
    }
    assert(format == NV12 || format == BGRA);
    //原始尺寸
    size_t basePixWidth = CVPixelBufferGetWidth(basePixelBuffer);
    size_t basePixHeight = CVPixelBufferGetHeight(basePixelBuffer);
    //原始尺寸
    size_t pixWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t pixHeight = CVPixelBufferGetHeight(pixelBuffer);
    //裁剪起始位置
    size_t startX = 0;
    size_t startY = 0;
    startX = startX & 0xFFFE;
    startY = startY & 0xFFFE;
    //填充起始位置
    size_t fillStartX = 0;
    size_t fillStartY = 0;
    fillStartX = fillStartX & 0xFFFE;
    fillStartY = fillStartY & 0xFFFE;
    //真实需裁减的尺寸,防止超出区域
    size_t clipW = MIN(pixWidth, basePixWidth);
    size_t clipH = MIN(pixHeight, basePixHeight);
    
    size_t clipSize = clipH * clipW;
    size_t clipFrameLength = clipH * clipW;
    if (CVPixelBufferGetPixelFormatType(basePixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || CVPixelBufferGetPixelFormatType(basePixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        clipFrameLength = clipH * clipW * 3 / 2;
        size_t b = CVPixelBufferGetBytesPerRow(pixelBuffer);
        size_t rows = CVPixelBufferGetHeight(pixelBuffer);
        size_t size = b*rows;
        clipFrameLength = size;
    }else{
        size_t b = CVPixelBufferGetBytesPerRow(pixelBuffer);
        size_t rows = CVPixelBufferGetHeight(pixelBuffer);
        size_t size = b*rows;
        clipFrameLength = size;
    }
    uint8_t *frame_tmp = malloc(clipFrameLength);
    memset(frame_tmp, 0x80, clipFrameLength);
    
    //先拷贝需要的数据
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    if (CVPixelBufferGetPixelFormatType(basePixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || CVPixelBufferGetPixelFormatType(basePixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        //获取CVImageBufferRef中的y数据
        uint8_t *y_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        //获取CMVImageBufferRef中的uv数据
        uint8_t *uv_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        
        //Y通道数据大小
        size_t yClipH = clipH;
        size_t yClipW = clipW;
        
        size_t ori_bpr0 = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        size_t ori_bpr1 = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        
        //提取Y数据
        for (size_t i = 0; i < yClipH; i++) {
            size_t oH = startY + i;
            size_t srcPos = startX + ori_bpr0 * oH;
            memcpy(frame_tmp+yClipW * i, y_frame+srcPos, yClipW);
        }
        
        //uv通道数据大小
        size_t uvClipH = clipH / 2;
        size_t uvClipW = clipW;

        //提取UV数据
        for (size_t i = 0; i < uvClipH; i++) {
            size_t oH = startY / 2 + i;
            size_t srcPos =  startX + ori_bpr1 * oH;
            size_t desPos = clipSize + uvClipW * i;
            memcpy(frame_tmp+desPos, uv_frame+srcPos, uvClipW);
        }
    }else{
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        size_t b = CVPixelBufferGetBytesPerRow(pixelBuffer);
        size_t rows = CVPixelBufferGetHeight(pixelBuffer);
        for (int i = 0; i < b; i++) {
            memcpy(frame_tmp+rows*i, rgba_frame+rows*i, rows);
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    size_t bpr0 = CVPixelBufferGetBytesPerRowOfPlane(basePixelBuffer, 0);
    size_t bpr1 = CVPixelBufferGetBytesPerRowOfPlane(basePixelBuffer, 1);
    
    CVPixelBufferLockBaseAddress(basePixelBuffer, 0);
    if (CVPixelBufferGetPixelFormatType(basePixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || CVPixelBufferGetPixelFormatType(basePixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        //Y通道数据大小
        size_t yClipH = clipH;
        size_t yClipW = clipW;
        //uv通道数据大小
        size_t uvClipH = clipH / 2;
        size_t uvClipW = clipW;
        //填充Y通道数据
        uint8_t *yPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 0);
        for (int row = 0; row < yClipH; row++) {
            size_t oH = fillStartY + row;
            size_t desPos = fillStartX + bpr0 * oH;
            memcpy(yPlane + desPos, frame_tmp + row * yClipW, yClipW);
        }
        //填充UV通道数据
        uint8_t *uvPlane = CVPixelBufferGetBaseAddressOfPlane(basePixelBuffer, 1);
        for (int row = 0; row < uvClipH; row++) {
            size_t oH = fillStartY / 2 + row;
            size_t desPos =  fillStartX + bpr1 * oH;
            memcpy(uvPlane + desPos, frame_tmp + yClipW * yClipH + row * uvClipW, uvClipW);
        }
    }else{
        uint8_t *rgba_frame = CVPixelBufferGetBaseAddress(basePixelBuffer);
//        memcpy(rgba_frame, frame_tmp+0, MIN(sizeof(frame_tmp),sizeof(rgba_frame)));
        size_t b = CVPixelBufferGetBytesPerRow(basePixelBuffer);
        size_t rows = CVPixelBufferGetHeight(basePixelBuffer);
        for (int i = 0; i < b; i++) {
            memcpy(rgba_frame+rows*i, frame_tmp+rows*i, rows);
        }
    }
    
    CVPixelBufferUnlockBaseAddress(basePixelBuffer, 0);
    free(frame_tmp);
}

//裁剪CVPixelBufferRef
-(CVPixelBufferRef)clipPixBuffer2:(CVPixelBufferRef)buffer rect:(CGRect)rect{

    CVPixelBufferLockBaseAddress(buffer, 0);

    size_t num=CVPixelBufferGetPlaneCount(buffer);

    void * address[num];

    size_t width[num];

    size_t height[num];

    size_t bytes[num];

    for (size_t i = 0; i != num; i++) {

        address[i] = CVPixelBufferGetBaseAddressOfPlane(buffer, i);

        width[i] = CVPixelBufferGetWidthOfPlane(buffer, i);

        height[i] = CVPixelBufferGetHeightOfPlane(buffer, i);

        bytes[i] = CVPixelBufferGetBytesPerRowOfPlane(buffer, i);

        size_t startpos = rect.origin.y * bytes[i] + rect.origin.x * (bytes[i] / width[i]);

        address[i] = address[i] + startpos / (bytes[i] / width[i]);

    }

    CVPixelBufferRef re = NULL;

    CVPixelBufferCreateWithPlanarBytes(kCFAllocatorDefault, rect.size.width, rect.size.height, CVPixelBufferGetPixelFormatType(buffer), NULL, CVPixelBufferGetDataSize(buffer), num, address, width, height, bytes, NULL, NULL, NULL, &re);

    CVPixelBufferUnlockBaseAddress(buffer, 0);

    return re;
}

@end
