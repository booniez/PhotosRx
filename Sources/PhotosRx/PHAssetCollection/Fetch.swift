import Photos

// 定义相册获取策略协议
protocol AlbumFetchStrategy {
    var fetchType: PHAssetCollectionType { get }
}

// 策略实现 - 获取智能相册
struct SmartAlbumFetchStrategy: AlbumFetchStrategy {
    var fetchType: PHAssetCollectionType { .smartAlbum }
}

// 策略实现 - 获取用户相册
struct UserAlbumFetchStrategy: AlbumFetchStrategy {
    var fetchType: PHAssetCollectionType { .album }
}

// PhotoFetchAssetCollection 扩展，使用泛型和策略模式
public extension PhotoFetchAssetCollection {

    // 使用泛型来根据不同的策略获取相册集合
    static func fetchAlbums<S: AlbumFetchStrategy>(
        with strategy: S,
        options: PHFetchOptions?
    ) -> PHFetchResult<PHAssetCollection> {
        PHAssetCollection.fetchAssetCollections(
            with: strategy.fetchType,
            subtype: .any,
            options: options
        )
    }

    // 枚举所有相册的泛型方法
    static func enumerateAllAlbums(
        options: PHFetchOptions?,
        usingBlock: @escaping (PHAssetCollection, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        // 使用不同策略获取相册
        let smartAlbums = fetchAlbums(with: SmartAlbumFetchStrategy(), options: options)
        let userAlbums = fetchAlbums(with: UserAlbumFetchStrategy(), options: options)
        let albums: [PHFetchResult<PHAssetCollection>] = [smartAlbums, userAlbums]
        
        var stopAlbums = false
        for result in albums {
            result.enumerateObjects { (collection, index, stop) in
                if collection.estimatedAssetCount > 0 && !collection.isFilteredAlbum {
                    usingBlock(collection, index, stop)
                    stopAlbums = stop.pointee.boolValue
                }
            }
            if stopAlbums {
                break
            }
        }
    }

    // 获取相机胶卷相册，利用策略
    static func fetchCameraRollAlbum(options: PHFetchOptions?) -> PHAssetCollection? {
        let smartAlbums = fetchAlbums(with: SmartAlbumFetchStrategy(), options: options)
        var assetCollection: PHAssetCollection?
        smartAlbums.enumerateObjects { (collection, _, stop) in
            if collection.isCameraRoll && collection.estimatedAssetCount > 0 {
                assetCollection = collection
                stop.initialize(to: true)
            }
        }
        return assetCollection
    }

    // 根据配置获取相册集合
    static func fetchAssetCollections(
        _ config: PickerConfiguration,
        localCount: Int,
        coverImage: UIImage?,
        options: PHFetchOptions,
        usingBlock: @escaping (PhotoAssetCollection, UnsafeMutablePointer<ObjCBool>) -> Bool
    ) -> [PhotoAssetCollection] {
        if !config.allowLoadPhotoLibrary {
            return []
        }

        if config.creationDate {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: config.creationDate)]
        }

        var assetCollections: [PhotoAssetCollection] = []
        fetchAssetCollections(options: options) { assetCollection, isCameraRoll, stop in
            if usingBlock(assetCollection, stop) {
                assetCollection.count += localCount
                if isCameraRoll {
                    assetCollections.insert(assetCollection, at: 0)
                } else {
                    assetCollections.append(assetCollection)
                }
            }
        }

        if let collection = assetCollections.first {
            collection.count += localCount
            if let coverImage = coverImage {
                collection.realCoverImage = coverImage
            }
        }
        return assetCollections
    }

    // 优化相机相册获取逻辑，利用策略
    static func fetchCameraAssetCollection(
        _ config: PickerConfiguration,
        options: PHFetchOptions
    ) -> PhotoAssetCollection? {
        if !config.allowLoadPhotoLibrary { return nil }

        if config.creationDate {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: config.creationDate)]
        }

        var collection: PHAssetCollection?

        if let localIdentifier = self.cameraAlbumLocalIdentifier,
           self.shouldUseLocalIdentifier(config: config) {
            collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
        }

        if collection == nil {
            collection = self.fetchCameraRollAlbum(options: nil)
            UserDefaults.standard.set(collection?.localIdentifier, forKey: PhotoManager.CameraAlbumLocal.identifier.rawValue)
            UserDefaults.standard.set(config.selectOptions.rawValue, forKey: PhotoManager.CameraAlbumLocal.identifierType.rawValue)
            UserDefaults.standard.set(Locale.preferredLanguages.first, forKey: PhotoManager.CameraAlbumLocal.language.rawValue)
        }

        guard let validCollection = collection else { return nil }

        let assetCollection = PhotoAssetCollection(collection: validCollection, options: options)
        assetCollection.isCameraRoll = true
        assetCollection.fetchOrUpdateResult()

        return assetCollection
    }

    // MARK: - Helpers
    private static func shouldUseLocalIdentifier(config: PickerConfiguration) -> Bool {
        if let localOptions = self.cameraAlbumLocalIdentifierSelectOptions,
           let localLanguage = self.cameraAlbumLocalLanguage,
           localLanguage == Locale.preferredLanguages.first,
           self.cameraAlbumLocalIdentifier != nil,
           (localOptions.isPhoto && localOptions.isVideo) || localOptions == config.selectOptions {
            return true
        }
        return false
    }

    private static var cameraAlbumLocalIdentifierSelectOptions: PickerAssetOptions? {
        PickerAssetOptions(rawValue: UserDefaults.standard.integer(forKey: PhotoManager.CameraAlbumLocal.identifierType.rawValue))
    }

    private static var cameraAlbumLocalLanguage: String? {
        UserDefaults.standard.string(forKey: PhotoManager.CameraAlbumLocal.language.rawValue)
    }

    private static var cameraAlbumLocalIdentifier: String? {
        UserDefaults.standard.string(forKey: PhotoManager.CameraAlbumLocal.identifier.rawValue)
    }
}

// Extension for PHAssetCollection
private extension PHAssetCollection {
    var isFilteredAlbum: Bool {
        return [205, 215, 212, 204, 1000000201].contains(self.assetCollectionSubtype.rawValue)
    }

    var isCameraRoll: Bool {
        return self.assetCollectionSubtype == .smartAlbumUserLibrary
    }
}
