//
//  MIKMIDISequence.m
//  MIDI Files Testbed
//
//  Created by Andrew Madsen on 5/21/14.
//  Copyright (c) 2014 Mixed In Key. All rights reserved.
//

#import "MIKMIDISequence.h"
#import <AudioToolbox/AudioToolbox.h>
#import "MIKMIDITrack.h"


@interface MIKMIDISequence ()

@property (nonatomic) MusicSequence musicSequence;
@property (strong, nonatomic) MIKMIDITrack *tempoTrack;
@property (strong, nonatomic) NSArray *tracks;

@end


@implementation MIKMIDISequence

#pragma mark - Lifecycle

+ (instancetype)sequence
{
    return [[self alloc] init];
}

- (instancetype)init
{
    MusicSequence sequence;
    OSStatus err = NewMusicSequence(&sequence);
    if (err) {
        NSLog(@"NewMusicSequence() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        return nil;
    }

    return [self initWithMusicSequence:sequence];
}

+ (instancetype)sequenceWithFileAtURL:(NSURL *)fileURL error:(NSError **)error;
{
    return [[self alloc] initWithFileAtURL:fileURL error:error];
}

- (instancetype)initWithFileAtURL:(NSURL *)fileURL error:(NSError **)error;
{
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:error];
    return data ? [self initWithData:data] : nil;
}

+ (instancetype)sequenceWithData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

- (instancetype)initWithData:(NSData *)data
{
    MusicSequence sequence;
    OSStatus err = NewMusicSequence(&sequence);
    if (err) {
        NSLog(@"NewMusicSequence() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        return nil;
    }

    err = MusicSequenceFileLoadData(sequence, (__bridge CFDataRef)data, kMusicSequenceFile_MIDIType, 0);
    if (err) {
        NSLog(@"MusicSequenceFileLoadData() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        return nil;
    }

    return [self initWithMusicSequence:sequence];
}

+ (instancetype)sequenceWithMusicSequence:(MusicSequence)musicSequence
{
    return [[self alloc] initWithMusicSequence:musicSequence];
}

- (instancetype)initWithMusicSequence:(MusicSequence)musicSequence
{
    if (self = [super init]) {
        OSStatus err = MusicSequenceSetUserCallback(musicSequence, MIKSequenceCallback, NULL);
        if (err) NSLog(@"MusicSequenceSetUserCallback() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        self.musicSequence = musicSequence;

        MusicTrack tempoTrack;
        err = MusicSequenceGetTempoTrack(musicSequence, &tempoTrack);
        if (err) NSLog(@"MusicSequenceGetTempoTrack() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        self.tempoTrack = [MIKMIDITrack trackWithSequence:self musicTrack:tempoTrack];

        UInt32 numTracks = 0;
        err = MusicSequenceGetTrackCount(musicSequence, &numTracks);
        if (err) NSLog(@"MusicSequenceGetTrackCount() failed with error %d in %s.", err, __PRETTY_FUNCTION__);

        NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:numTracks];

        for (UInt32 i = 0; i < numTracks; i++) {
            MusicTrack musicTrack;
            err = MusicSequenceGetIndTrack(musicSequence, i, &musicTrack);
            if (err) NSLog(@"MusicSequenceGetIndTrack() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
            [tracks addObject:[MIKMIDITrack trackWithSequence:self musicTrack:musicTrack]];
        }
        self.tracks = tracks;
    }
    
    return self;
}

- (void)dealloc
{
    OSStatus err = DisposeMusicSequence(_musicSequence);
    if (err) NSLog(@"DisposeMusicSequence() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
}

#pragma mark - Adding and Removing Tracks

- (MIKMIDITrack *)createNewTrack
{
    MusicTrack musicTrack;
    OSStatus err = MusicSequenceNewTrack(self.musicSequence, &musicTrack);
    if (err) {
        NSLog(@"MusicSequenceNewTrack() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        return nil;
    }

    MIKMIDITrack *track = [MIKMIDITrack trackWithSequence:self musicTrack:musicTrack];

    if (track) {
        NSMutableArray *tracks = [self.tracks mutableCopy];
        [tracks addObject:track];
        self.tracks = tracks;
    }

    return track;
}

- (BOOL)removeTrack:(MIKMIDITrack *)track
{
    OSStatus err = MusicSequenceDisposeTrack(self.musicSequence, track.musicTrack);
    if (err) {
        NSLog(@"MusicSequenceDisposeTrack() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        return NO;
    }

    NSMutableArray *tracks = [self.tracks mutableCopy];
    [tracks removeObject:track];
    self.tracks = tracks;

    return YES;
}

#pragma mark - File Saving

- (BOOL)writeToURL:(NSURL *)fileURL error:(NSError *__autoreleasing *)error
{
    return [self.dataValue writeToURL:fileURL options:NSDataWritingAtomic error:error];
}

#pragma mark - Callback

static void MIKSequenceCallback(void *inClientData, MusicSequence inSequence, MusicTrack inTrack, MusicTimeStamp inEventTime, const MusicEventUserData *inEventData, MusicTimeStamp inStartSliceBeat, MusicTimeStamp inEndSliceBeat)
{
    NSLog(@"CALLED BACK!");
}

#pragma mark - Description

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@ tempo track: %@ tracks: %@", [super description], self.tempoTrack, self.tracks];
}

#pragma mark - Properties

- (MusicTimeStamp)length
{
    MusicTimeStamp length = 0;
    for (MIKMIDITrack *track in self.tracks) {
        MusicTimeStamp trackLength = track.length + track.offset;
        if (trackLength > length) length = trackLength;
    }

    return length;
}

- (Float64)durationInSeconds
{
    Float64 duration = 0;
    OSStatus err = MusicSequenceGetSecondsForBeats(self.musicSequence, self.length, &duration);
    if (err) NSLog(@"MusicSequenceGetSecondsForBeats() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
    return duration;
}

- (NSData *)dataValue
{
    NSData *data;
    CFDataRef cfData = (__bridge CFDataRef)data;
    OSStatus err = MusicSequenceFileCreateData(self.musicSequence, kMusicSequenceFile_MIDIType, kMusicSequenceFileFlags_EraseFile, 0, &cfData);
    if (err) {
        NSLog(@"MusicSequenceFileCreateData() failed with error %d in %s.", err, __PRETTY_FUNCTION__);
        return nil;
    }
    return data;
}

@end
