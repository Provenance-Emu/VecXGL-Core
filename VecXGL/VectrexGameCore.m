/*
 Copyright (c) 2010 OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the OpenEmu Team nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

// We need to mess with core internals

#import "VectrexGameCore.h"
@import PVSupport;

#import <OpenGLES/ES2/GL.h>
#import "vecx.h"
#import "osint.h"

@interface VectrexGameCore () <PVVectrexSystemResponderClient>
{
    int videoWidth, videoHeight;
    NSString *romPath;
    NSString *overlayFile;
    BOOL overlayIsLoaded;
}
@end

VectrexGameCore *g_core;

@implementation VectrexGameCore

- (id)init {
    if (self = [super init])
    {
        videoWidth = 330 * 2;
        videoHeight = 410 * 2;
    }
    overlayIsLoaded = NO;

    g_core = self;
    return self;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error {
    romPath = path;
    osint_defaults();           //setup defaults including sound buffer
    openCart(path.fileSystemRepresentation);
    osint_gencolors();          //setup colors
    return YES;
}

- (void)executeFrameSkippingFrame:(BOOL)skip {
    // late init of the overlay

    // check fix, has to be REloaded at each frame, i mean really ?
    if (![overlayFile isEqualToString:@""] && !overlayIsLoaded)
    //if (![overlayFile isEqualToString:@""] && !overlayIsLoaded)
    {
        load_overlay((char *)overlayFile.fileSystemRepresentation);
        overlayIsLoaded = YES;
    }

    vecx_emu ((VECTREX_MHZ / 1000) * EMU_TIMER, 0);
    glFlush();
}

- (void)executeFrame {
    [self executeFrameSkippingFrame:NO];
}

- (void)startEmulation {
//    if(self.rate != 0) return;

    [super startEmulation];
    vecx_reset();

    NSFileManager *defaultFileManager = [NSFileManager defaultManager];
    if ([defaultFileManager fileExistsAtPath:[[romPath stringByDeletingPathExtension] stringByAppendingString:@".tga"]])
    {
        // Too early to load overlay, the context is not ready
        //load_overlay((char *)[[[romPath stringByDeletingPathExtension] stringByAppendingString:@".tga"] fileSystemRepresentation]);
        overlayFile = [[romPath stringByDeletingPathExtension] stringByAppendingString:@".tga"];
    }
}

- (void)updateSound:(uint8_t *)buff len:(int)len
{
    [[g_core ringBufferAtIndex:0] write:buff maxLength:len];
}

- (void)resetEmulation
{
    vecx_reset();
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    VECXState *state = saveVecxState();
    NSData *data = [NSData dataWithBytesNoCopy:state length:sizeof(VECXState) freeWhenDone:YES];

    NSError *error;
    BOOL succeeded = [data writeToFile:fileName options:0 error:&error];
    block(succeeded, error);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    NSError *error;
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:fileName options:0 error:&error];

    if (!data) {
        block(NO, error);
        return;
    }

    if (sizeof(VECXState) != data.length) {
        block(NO, [NSError errorWithDomain:@"org.provenance.GameCore.ErrorDomain" code:-1 userInfo:@{
            NSLocalizedFailureReasonErrorKey: @"The size of the saved file is different from the size of the state.",
        }]);
        return;
    }

    VECXState *state = (void *)data.bytes;
    loadVecxState(state);
}

- (CGSize)aspectSize
{
    return (CGSize){videoWidth, videoHeight};
}

- (CGRect)screenRect
{
    return CGRectMake(0, 0, videoWidth, videoHeight);
}

- (CGSize)bufferSize
{
    return CGSizeMake(videoWidth, videoHeight);
}

//- (OEGameCoreRendering)gameCoreRendering
//{
//    return OEGameCoreRenderingOpenGL2Video;
//}

- (BOOL)rendersToOpenGL
{
    return YES;
}

//- (BOOL)isDoubleBuffered {
//    return YES;
//}

- (const void *)videoBuffer
{
    return NULL;
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_BYTE; //GL_UNSIGNED_SHORT_4_4_4_4;
}

- (GLenum)internalPixelFormat
{
    return GL_RGBA;
}

- (double)audioSampleRate
{
    return 44100;
}

- (NSUInteger)audioBitDepth
{
    return 8;
}

- (NSTimeInterval)frameInterval
{
    return 50;
}

- (NSUInteger)channelCount
{
    return 1;
}

- (oneway void)didMoveVectrexJoystickDirection:(PVVectrexButton)button withValue:(CGFloat)value forPlayer:(NSInteger)player
{
    player -= 1;
    switch (button)
    {
        case PVVectrexAnalogUp:
            yAxis[player][0] = value * INT8_MAX;
            break;
        case PVVectrexAnalogDown:
            yAxis[player][1] = value * INT8_MIN;
            break;
        case PVVectrexAnalogLeft:
            xAxis[player][0] = value * INT8_MIN;
            break;
        case PVVectrexAnalogRight:
            xAxis[player][1] = value * INT8_MAX;
            break;
        default:
            break;
    }
}

// oneway void
- (void)didPushVectrexButton:(PVVectrexButton)button forPlayer:(NSInteger)player
{
    player -= 1;
    padData[player][button] = 1;
    
    osint_btnDown(button);
}

// oneway void
- (void)didReleaseVectrexButton:(PVVectrexButton)button forPlayer:(NSInteger)player
{
    player -= 1;
    padData[player][button] = 0;
    
    osint_btnUp(button);
}

@end
