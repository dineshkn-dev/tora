#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TOREncryptionPolicy) {
    TOREncryptionPolicyEnabled = 0,
    TOREncryptionPolicyForced = 1,
    TOREncryptionPolicyDisabled = 2
};

@interface TORSessionConfig : NSObject
@property(nonatomic) BOOL enableDHT;
@property(nonatomic) BOOL enableLSD;
@property(nonatomic) BOOL enableUPnP;
@property(nonatomic) BOOL enableNATPMP;
@property(nonatomic) BOOL enablePeerExchange;
@property(nonatomic) TOREncryptionPolicy encryptionPolicy;
@property(nonatomic) uint16_t listenPortStart;
@property(nonatomic) uint16_t listenPortEnd;
@property(nonatomic) NSInteger maxConnections;
@property(nonatomic) NSInteger maxUploads;
@property(nonatomic) NSInteger downloadRateLimitBytesPerSecond;
@property(nonatomic) NSInteger uploadRateLimitBytesPerSecond;
@property(nonatomic) NSInteger seedRatioLimitPercent;
@property(nonatomic) NSInteger seedTimeLimitSeconds;
@property(nonatomic) NSInteger seedTimeRatioLimitPercent;
@property(nonatomic, copy, nullable) NSURL *sessionStateURL;
@end

@interface TORTorrentFile : NSObject
@property(nonatomic) NSInteger index;
@property(nonatomic, copy) NSString *path;
@property(nonatomic) int64_t size;
@end

@interface TORPendingTorrent : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy, nullable) NSString *infoHash;
@property(nonatomic, copy) NSArray<TORTorrentFile *> *files;
@property(nonatomic, copy, nullable) NSURL *torrentFileURL;
@property(nonatomic, copy, nullable) NSString *magnetLink;
@end

@interface TORAddTorrentRequest : NSObject
@property(nonatomic, strong) TORPendingTorrent *pendingTorrent;
@property(nonatomic, strong) TORSessionConfig *sessionConfig;
@property(nonatomic, strong) NSURL *downloadDirectory;
@property(nonatomic, copy) NSIndexSet *selectedFileIndexes;
@property(nonatomic) BOOL startPaused;
@property(nonatomic, copy, nullable) NSURL *resumeDataURL;
@property(nonatomic) BOOL fetchMetadataOnly;
@end

typedef NS_ENUM(NSInteger, TORTorrentEventKind) {
    TORTorrentEventKindMetadataReceived = 0,
    TORTorrentEventKindResumeDataSaved = 1,
    TORTorrentEventKindError = 2
};

@interface TORTorrentEvent : NSObject
@property(nonatomic) TORTorrentEventKind kind;
@property(nonatomic, copy, nullable) NSString *torrentID;
@property(nonatomic, copy, nullable) NSString *message;
@property(nonatomic, strong, nullable) TORPendingTorrent *pendingTorrent;
@end

@interface TORTorrentStatus : NSObject
@property(nonatomic, copy) NSString *torrentID;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) double progress;
@property(nonatomic, copy) NSString *state;
@property(nonatomic) int64_t downloadRate;
@property(nonatomic) int64_t uploadRate;
@property(nonatomic) int64_t totalWanted;
@property(nonatomic) int64_t totalDone;
@property(nonatomic) int64_t totalUploaded;
@property(nonatomic) NSInteger seedingSeconds;
@property(nonatomic) BOOL hasMetadata;
@end

@interface TORLibtorrentClient : NSObject
- (instancetype)initWithConfig:(TORSessionConfig *)config error:(NSError **)error;
- (BOOL)applyConfig:(TORSessionConfig *)config error:(NSError **)error;
- (TORPendingTorrent *_Nullable)inspectTorrentFileAtURL:(NSURL *)url error:(NSError **)error;
- (TORPendingTorrent *_Nullable)inspectMagnet:(NSString *)magnet error:(NSError **)error;
- (NSString *_Nullable)addTorrent:(TORAddTorrentRequest *)request error:(NSError **)error;
- (TORPendingTorrent *_Nullable)metadataForTorrent:(NSString *)torrentID error:(NSError **)error;
- (BOOL)pauseTorrent:(NSString *)torrentID error:(NSError **)error;
- (BOOL)resumeTorrent:(NSString *)torrentID error:(NSError **)error;
- (BOOL)fetchMetadataForTorrent:(NSString *)torrentID error:(NSError **)error;
- (BOOL)setSelectedFileIndexes:(NSIndexSet *)selectedFileIndexes forTorrent:(NSString *)torrentID startPaused:(BOOL)startPaused error:(NSError **)error;
- (BOOL)removeTorrent:(NSString *)torrentID deleteData:(BOOL)deleteData error:(NSError **)error;
- (NSArray<TORTorrentStatus *> *)torrentStatuses;
- (NSArray<TORTorrentEvent *> *)drainEventsSavingResumeDataToDirectory:(NSURL *)directory;
- (BOOL)saveSessionState:(NSError **)error;
- (BOOL)requestResumeDataForAllTorrents:(NSError **)error;
- (void)shutdown;
@end

NS_ASSUME_NONNULL_END
