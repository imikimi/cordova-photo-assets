# cordova_photo_assets
Cordova Plugin for Accessing the Photo Assets on iOS and eventually Android

## Examples

### Simple Example

This example will list all assets for the first asset-collection found.

```coffeescript

document.addEventListener 'deviceready', ->
  PhotoAssets.setOptions currentAssetCollection: "all", ->
    console.log "all (local) photo assets selected, a photoAssetsChanged event will follow shortly"

document.addEventListener 'photoAssetsChanged', ({details})->
  {collections, currentCollectionKey, offset, assets} = details
  {collectionName} = collections[currentCollectionKey]

  console.log "PhotoAssets from Collection: #{collectionName}:"
  for asset in assets
    console.log "  asset #{offset++}: #{asset.assetKey}"
```

### Extended Example

This example shows how to get a list of all available collections, how to follow one specifically, and how to set all custom options.

```coffeescript

document.addEventListener 'deviceready', ->

  PhotoAssets.getCollections (assetCollections)->
    [{
      collectionKey
      collectionName
      estimatedAssetCount
    }] = assetCollections

    PhotoAssets.setOptions
      currentCollectionKey: collectionKey
      thumbnailSize: 270
      limit: 100
      offset: 0
      thumbnailQuality: 95
    , ->
      console.log "selected first asset collection: " + collectionName

document.addEventListener 'photoAssetsChanged', ({details})->
  # see previous example or API doc
```

## PhotoAssets API

#### getCollections
```coffeescript
PhotoAssets.getCollections successCallback, errorCallback

successCallback: (collections) ->
  [{collectionKey, collectionName, estimatedAssetCount}] = collections
```

Returns, via successCallback, an array of collections with the following properties each:

* collectionKey: unique identifier for the collection
  * Used to select the collection you want for thumbnails:
  * Ex: ```PhotoAssets.setOptions currentCollectionKey: collectionKey```
* collectionName: human-readable name for the collection
* estimatedAssetCount: (integer) estimated number of photos in the collection

#### setOptions
```coffeescript
PhotoAssets.setOptions options, successCallback, errorCallback

successCallback: ->
```

```options``` can be 0, 1 or more of the following. The missing options will not be changed.

* thumbnailSize:        (pixels)
* thumbnailQuality:     (0-100)
* limit:                (int >= 1) number of thumbnails to return starting from the current offset.
* offset:               (int >= 0) current thumbnail offset
* currentCollectionKey: (string) Use "all" for all local images. Otherwise, get collection keys from getCollections


#### getOptions
```coffeescript
PhotoAssets.getOptions successCallback, errorCallback

successCallback: (options) ->
```

Returns, via successCallback, the current value for all options as an ```options``` object.

#### getPhoto

```coffeescript
PhotoAssets.getPhoto
  assetKey:          "string" # required - see photoAssetsChanged
  maxSize:           123      # width and height <= maxSize. default: no max
  quality:           95       # 0 to 100 JPG quality. default: 95
, successCallback, errorCallback

successCallback: ({
  assetKey            # unique key for this asset
  photoUrl            # link to the app-local image file
  pixelWidth          # width of the app-local image file
  pixelHeight         # height of the app-local image file
  originalPixelWidth  # width of the original asset
  originalPixelHeight # height of the original asset
}) ->
```

This call fetches a photo given its ```assetKey```. Asset keys are provided via ```photoAssetsChanged``` events. On success, a version of the photo asset has been writen to app-local storage and is accessable via ```photoUrl```. This temporary file is unique to this call and will stick around until the next time the plugin is initialized - sometime after the next app start.

#### photoAssetsChanged event

```coffeescript
document.addEventListener 'photoAssetsChanged', ({details})->
  {
    options             # same object returned by getOptions
    collections         # same object returned by getCollections
    assets              # array of all assets in the current window with valid thumbnails
  } = details

  [{
    assetKey            # unique key for this asset
    photoUrl            # url to fetch the thumbnail photo
    pixelWidth          # width of the thumbnail
    pixelHeight         # height of the thumbnail
    originalPixelWidth  # width of the original asset
    originalPixelHeight # height of the original asset
  }] = assets
```

## Notes

### Temporary Files

This plugin creates temporary files in its own temporary folder. Each time the plugin is initialized, it deletes all existing temporary files. Plugin init happens on the first API call.

# Future

```
iOS supports the following additional attributes for some collections:

  startDate
  endDate
  approximateLocation
  localizedLocationNames

And the following additional asset properties:

  location, duration, favorite, hidden
```
