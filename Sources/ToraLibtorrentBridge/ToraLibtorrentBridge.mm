#import "ToraLibtorrentBridge.h"

#if __has_include(<libtorrent/torrent_info.hpp>)
#define TORA_HAS_LIBTORRENT 1
#import <libtorrent/session.hpp>
#import <libtorrent/session_params.hpp>
#import <libtorrent/settings_pack.hpp>
#import <libtorrent/add_torrent_params.hpp>
#import <libtorrent/magnet_uri.hpp>
#import <libtorrent/torrent_info.hpp>
#import <libtorrent/torrent_status.hpp>
#import <libtorrent/torrent_handle.hpp>
#import <libtorrent/torrent_flags.hpp>
#import <libtorrent/read_resume_data.hpp>
#import <libtorrent/write_resume_data.hpp>
#import <libtorrent/bencode.hpp>
#import <libtorrent/alert_types.hpp>
#import <libtorrent/error_code.hpp>
#import <libtorrent/file_storage.hpp>
#import <libtorrent/info_hash.hpp>
#import <memory>
#import <mutex>
#import <string>
#import <unordered_map>
#import <vector>
#else
#define TORA_HAS_LIBTORRENT 0
#endif

@implementation TORSessionConfig
@end

@implementation TORTorrentFile
@end

@implementation TORPendingTorrent
@end

@implementation TORAddTorrentRequest
@end

@implementation TORTorrentStatus
@end

@implementation TORTorrentEvent
@end

static NSError *TORBridgeUnavailableError(void) {
    return [NSError errorWithDomain:@"Tora.LibtorrentBridge"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: @"libtorrent is not linked yet."}];
}

static NSError *TORBridgeError(NSString *message) {
    return [NSError errorWithDomain:@"Tora.LibtorrentBridge"
                               code:2
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#if TORA_HAS_LIBTORRENT
static NSString *TORString(std::string const& value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

static std::string TORStdString(NSString *value) {
    return value == nil ? std::string() : std::string(value.UTF8String);
}

static std::string TORStdStringFromURLPath(NSURL *url) {
    return url == nil ? std::string() : std::string(url.path.UTF8String);
}

static libtorrent::settings_pack TORSettingsPack(TORSessionConfig *config) {
    libtorrent::settings_pack settings;
    settings.set_bool(libtorrent::settings_pack::enable_dht, config.enableDHT);
    settings.set_bool(libtorrent::settings_pack::enable_lsd, config.enableLSD);
    settings.set_bool(libtorrent::settings_pack::enable_upnp, config.enableUPnP);
    settings.set_bool(libtorrent::settings_pack::enable_natpmp, config.enableNATPMP);
    settings.set_bool(libtorrent::settings_pack::listen_system_port_fallback, false);
    settings.set_str(
        libtorrent::settings_pack::listen_interfaces,
        "0.0.0.0:" + std::to_string(config.listenPortStart) + "-" + std::to_string(config.listenPortEnd)
    );
    settings.set_int(
        libtorrent::settings_pack::alert_mask,
        libtorrent::alert_category::error
        | libtorrent::alert_category::status
        | libtorrent::alert_category::storage
    );
    if (config.maxConnections > 0) {
        settings.set_int(libtorrent::settings_pack::connections_limit, static_cast<int>(config.maxConnections));
    }
    if (config.uploadRateLimitBytesPerSecond > 0) {
        settings.set_int(libtorrent::settings_pack::upload_rate_limit, static_cast<int>(config.uploadRateLimitBytesPerSecond));
    }
    if (config.downloadRateLimitBytesPerSecond > 0) {
        settings.set_int(libtorrent::settings_pack::download_rate_limit, static_cast<int>(config.downloadRateLimitBytesPerSecond));
    }

    switch (config.encryptionPolicy) {
        case TOREncryptionPolicyForced:
            settings.set_int(libtorrent::settings_pack::out_enc_policy, libtorrent::settings_pack::pe_forced);
            settings.set_int(libtorrent::settings_pack::in_enc_policy, libtorrent::settings_pack::pe_forced);
            break;
        case TOREncryptionPolicyDisabled:
            settings.set_int(libtorrent::settings_pack::out_enc_policy, libtorrent::settings_pack::pe_disabled);
            settings.set_int(libtorrent::settings_pack::in_enc_policy, libtorrent::settings_pack::pe_disabled);
            break;
        case TOREncryptionPolicyEnabled:
        default:
            settings.set_int(libtorrent::settings_pack::out_enc_policy, libtorrent::settings_pack::pe_enabled);
            settings.set_int(libtorrent::settings_pack::in_enc_policy, libtorrent::settings_pack::pe_enabled);
            break;
    }
    return settings;
}

static TORPendingTorrent *TORPendingFromTorrentInfo(libtorrent::torrent_info const& info) {
    TORPendingTorrent *pending = [[TORPendingTorrent alloc] init];
    pending.name = TORString(info.name());
    pending.infoHash = TORString(info.info_hashes().get_best().to_string());

    NSMutableArray<TORTorrentFile *> *files = [[NSMutableArray alloc] init];
    const libtorrent::file_storage &storage = info.files();
    for (libtorrent::file_index_t i(0); i < storage.end_file(); ++i) {
        TORTorrentFile *file = [[TORTorrentFile alloc] init];
        file.index = static_cast<NSInteger>(static_cast<int>(i));
        file.path = TORString(storage.file_path(i));
        file.size = storage.file_size(i);
        [files addObject:file];
    }
    pending.files = files;
    return pending;
}

static NSString *TORStateString(libtorrent::torrent_status::state_t state) {
    switch (state) {
        case libtorrent::torrent_status::checking_files:
        case libtorrent::torrent_status::checking_resume_data:
            return @"checking";
        case libtorrent::torrent_status::downloading_metadata:
            return @"downloadingMetadata";
        case libtorrent::torrent_status::downloading:
            return @"downloading";
        case libtorrent::torrent_status::finished:
            return @"finished";
        case libtorrent::torrent_status::seeding:
            return @"seeding";
        default:
            return @"paused";
    }
}

@interface TORLibtorrentClient () {
    std::unique_ptr<libtorrent::session> _session;
    NSURL *_sessionStateURL;
    std::mutex _mutex;
    std::unordered_map<std::string, libtorrent::torrent_handle> _handles;
}
@end
#endif

@implementation TORLibtorrentClient

- (instancetype)initWithConfig:(TORSessionConfig *)config error:(NSError **)error {
    self = [super init];
#if TORA_HAS_LIBTORRENT
    if (self != nil) {
        if (config.listenPortStart == 0 || config.listenPortEnd == 0 || config.listenPortStart > config.listenPortEnd) {
            if (error != nil) {
                *error = TORBridgeError(@"Invalid listen port range.");
            }
            return nil;
        }

        libtorrent::session_params params;
        params.settings = TORSettingsPack(config);
        _sessionStateURL = config.sessionStateURL;
        _session = std::make_unique<libtorrent::session>(std::move(params));
    }
#endif
    return self;
}

- (TORPendingTorrent *)inspectTorrentFileAtURL:(NSURL *)url error:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    if (!url.isFileURL) {
        if (error != nil) {
            *error = TORBridgeError(@"Torrent file URL must be a local file URL.");
        }
        return nil;
    }

    libtorrent::error_code ec;
    auto info = std::make_unique<libtorrent::torrent_info>(url.path.UTF8String, ec);
    if (ec) {
        if (error != nil) {
            NSString *message = [NSString stringWithUTF8String:ec.message().c_str()];
            *error = TORBridgeError(message ?: @"Failed to read torrent metadata.");
        }
        return nil;
    }

    TORPendingTorrent *pending = [[TORPendingTorrent alloc] init];
    pending = TORPendingFromTorrentInfo(*info);
    pending.torrentFileURL = url;
    return pending;
#else
    if (error != nil) {
        *error = TORBridgeUnavailableError();
    }
    return nil;
#endif
}

- (TORPendingTorrent *)inspectMagnet:(NSString *)magnet error:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    libtorrent::error_code ec;
    libtorrent::add_torrent_params params = libtorrent::parse_magnet_uri(TORStdString(magnet), ec);
    if (ec) {
        if (error != nil) {
            *error = TORBridgeError(TORString(ec.message()));
        }
        return nil;
    }

    TORPendingTorrent *pending = [[TORPendingTorrent alloc] init];
    pending.name = params.name.empty() ? @"Magnet Torrent" : TORString(params.name);
    pending.infoHash = TORString(params.info_hashes.get_best().to_string());
    pending.files = @[];
    pending.magnetLink = magnet;
    return pending;
#else
    if (error != nil) {
        *error = TORBridgeUnavailableError();
    }
    return nil;
#endif
}

- (NSString *)addTorrent:(TORAddTorrentRequest *)request error:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    if (_session == nullptr) {
        if (error != nil) {
            *error = TORBridgeUnavailableError();
        }
        return nil;
    }
    if (!request.downloadDirectory.isFileURL) {
        if (error != nil) {
            *error = TORBridgeError(@"Download directory must be a local file URL.");
        }
        return nil;
    }

    libtorrent::error_code ec;
    libtorrent::add_torrent_params params;
    bool loadedResumeData = false;

    if (request.resumeDataURL != nil && [[NSFileManager defaultManager] fileExistsAtPath:request.resumeDataURL.path]) {
        NSData *data = [NSData dataWithContentsOfURL:request.resumeDataURL options:0 error:nil];
        if (data != nil) {
            auto bytes = static_cast<char const *>(data.bytes);
            params = libtorrent::read_resume_data(libtorrent::span<char const>(bytes, data.length), ec);
            loadedResumeData = !ec;
            ec.clear();
        }
    }

    if (!loadedResumeData && request.pendingTorrent.torrentFileURL != nil) {
        auto info = std::make_shared<libtorrent::torrent_info>(request.pendingTorrent.torrentFileURL.path.UTF8String, ec);
        if (ec) {
            if (error != nil) {
                *error = TORBridgeError(TORString(ec.message()));
            }
            return nil;
        }
        params.ti = info;
        params.name = info->name();
        params.file_priorities.assign(static_cast<size_t>(info->num_files()), libtorrent::dont_download);
        for (NSUInteger idx = request.selectedFileIndexes.firstIndex;
             idx != NSNotFound;
             idx = [request.selectedFileIndexes indexGreaterThanIndex:idx]) {
            if (idx < params.file_priorities.size()) {
                params.file_priorities[idx] = libtorrent::default_priority;
            }
        }
    } else if (!loadedResumeData && request.pendingTorrent.magnetLink != nil) {
        params = libtorrent::parse_magnet_uri(TORStdString(request.pendingTorrent.magnetLink), ec);
        if (ec) {
            if (error != nil) {
                *error = TORBridgeError(TORString(ec.message()));
            }
            return nil;
        }
        params.name = TORStdString(request.pendingTorrent.name);
    } else {
        if (error != nil) {
            *error = TORBridgeError(@"Pending torrent does not contain a torrent file or magnet link.");
        }
        return nil;
    }

    params.save_path = request.downloadDirectory.path.UTF8String;
    if (!request.sessionConfig.enablePeerExchange) {
        params.flags |= libtorrent::torrent_flags::disable_pex;
    }
    if (request.startPaused) {
        params.flags &= ~libtorrent::torrent_flags::auto_managed;
        params.flags |= libtorrent::torrent_flags::paused;
    }

    libtorrent::torrent_handle handle;
    {
        std::lock_guard<std::mutex> lock(_mutex);
        handle = _session->add_torrent(params, ec);
        if (ec) {
            if (error != nil) {
                *error = TORBridgeError(TORString(ec.message()));
            }
            return nil;
        }
        std::string key = handle.info_hashes().get_best().to_string();
        _handles[key] = handle;
        return TORString(key);
    }
#else
    if (error != nil) {
        *error = TORBridgeUnavailableError();
    }
    return nil;
#endif
}

- (BOOL)pauseTorrent:(NSString *)torrentID error:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _handles.find(TORStdString(torrentID));
    if (it == _handles.end() || !it->second.is_valid()) {
        if (error != nil) {
            *error = TORBridgeError(@"Torrent not found.");
        }
        return NO;
    }
    it->second.pause();
    return YES;
#else
    if (error != nil) {
        *error = TORBridgeUnavailableError();
    }
    return NO;
#endif
}

- (BOOL)resumeTorrent:(NSString *)torrentID error:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _handles.find(TORStdString(torrentID));
    if (it == _handles.end() || !it->second.is_valid()) {
        if (error != nil) {
            *error = TORBridgeError(@"Torrent not found.");
        }
        return NO;
    }
    it->second.resume();
    return YES;
#else
    if (error != nil) {
        *error = TORBridgeUnavailableError();
    }
    return NO;
#endif
}

- (BOOL)removeTorrent:(NSString *)torrentID deleteData:(BOOL)deleteData error:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _handles.find(TORStdString(torrentID));
    if (it == _handles.end() || !it->second.is_valid()) {
        if (error != nil) {
            *error = TORBridgeError(@"Torrent not found.");
        }
        return NO;
    }
    libtorrent::remove_flags_t flags{};
    if (deleteData) {
        flags |= libtorrent::session::delete_files;
    }
    _session->remove_torrent(it->second, flags);
    _handles.erase(it);
    return YES;
#else
    if (error != nil) {
        *error = TORBridgeUnavailableError();
    }
    return NO;
#endif
}

- (NSArray<TORTorrentEvent *> *)drainEventsSavingResumeDataToDirectory:(NSURL *)directory {
#if TORA_HAS_LIBTORRENT
    NSMutableArray<TORTorrentEvent *> *events = [[NSMutableArray alloc] init];
    if (_session == nullptr) {
        return events;
    }

    std::vector<libtorrent::alert *> alerts;
    {
        std::lock_guard<std::mutex> lock(_mutex);
        _session->pop_alerts(&alerts);
    }

    for (libtorrent::alert *alert : alerts) {
        if (auto *metadata = libtorrent::alert_cast<libtorrent::metadata_received_alert>(alert)) {
            libtorrent::torrent_handle handle = metadata->handle;
            if (!handle.is_valid()) {
                continue;
            }
            std::string key = handle.info_hashes().get_best().to_string();
            auto info = handle.torrent_file();
            if (!info) {
                continue;
            }

            TORTorrentEvent *event = [[TORTorrentEvent alloc] init];
            event.kind = TORTorrentEventKindMetadataReceived;
            event.torrentID = TORString(key);
            event.pendingTorrent = TORPendingFromTorrentInfo(*info);
            [events addObject:event];
        } else if (auto *resume = libtorrent::alert_cast<libtorrent::save_resume_data_alert>(alert)) {
            std::string key = resume->handle.info_hashes().get_best().to_string();
            std::vector<char> buffer = libtorrent::write_resume_data_buf(resume->params);
            NSURL *url = [[directory URLByAppendingPathComponent:TORString(key)] URLByAppendingPathExtension:@"fastresume"];
            NSData *data = [NSData dataWithBytes:buffer.data() length:buffer.size()];
            [data writeToURL:url options:NSDataWritingAtomic error:nil];

            TORTorrentEvent *event = [[TORTorrentEvent alloc] init];
            event.kind = TORTorrentEventKindResumeDataSaved;
            event.torrentID = TORString(key);
            [events addObject:event];
        } else if (auto *failed = libtorrent::alert_cast<libtorrent::save_resume_data_failed_alert>(alert)) {
            TORTorrentEvent *event = [[TORTorrentEvent alloc] init];
            event.kind = TORTorrentEventKindError;
            event.torrentID = TORString(failed->handle.info_hashes().get_best().to_string());
            event.message = TORString(failed->message());
            [events addObject:event];
        }
    }
    return events;
#else
    return @[];
#endif
}

- (NSArray<TORTorrentStatus *> *)torrentStatuses {
#if TORA_HAS_LIBTORRENT
    NSMutableArray<TORTorrentStatus *> *statuses = [[NSMutableArray alloc] init];
    std::lock_guard<std::mutex> lock(_mutex);
    for (auto it = _handles.begin(); it != _handles.end();) {
        libtorrent::torrent_handle handle = it->second;
        if (!handle.is_valid()) {
            it = _handles.erase(it);
            continue;
        }

        libtorrent::torrent_status status = handle.status();
        TORTorrentStatus *bridgeStatus = [[TORTorrentStatus alloc] init];
        bridgeStatus.torrentID = TORString(it->first);
        bridgeStatus.name = TORString(status.name);
        bridgeStatus.progress = status.progress;
        bridgeStatus.state = bool(status.flags & libtorrent::torrent_flags::paused) ? @"paused" : TORStateString(status.state);
        bridgeStatus.downloadRate = status.download_payload_rate;
        bridgeStatus.uploadRate = status.upload_payload_rate;
        bridgeStatus.totalWanted = status.total_wanted;
        bridgeStatus.totalDone = status.total_wanted_done;
        [statuses addObject:bridgeStatus];
        ++it;
    }
    return statuses;
#else
    return @[];
#endif
}

- (BOOL)saveSessionState:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    // Session-level state is intentionally minimal for now; torrents are restored
    // from app-owned metadata plus per-torrent resume data.
    return YES;
#else
    return YES;
#endif
}

- (BOOL)requestResumeDataForAllTorrents:(NSError **)error {
#if TORA_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(_mutex);
    for (auto const& pair : _handles) {
        if (pair.second.is_valid()) {
            pair.second.save_resume_data(libtorrent::torrent_handle::only_if_modified);
        }
    }
    return YES;
#else
    if (error != nil) {
        *error = TORBridgeUnavailableError();
    }
    return NO;
#endif
}

- (void)shutdown {
#if TORA_HAS_LIBTORRENT
    std::lock_guard<std::mutex> lock(_mutex);
    _handles.clear();
    _session.reset();
#endif
}

@end
