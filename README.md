# cordova_photo_assets
Cordova Plugin for Accessing the Photo Assets on iOS and eventually Android

## API

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

### PhotoAssets API DETAILS

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
  assetKey: "string" # required - see photoAssetsChanged
  maxSize:  123      # width and height <= maxSize. default: no max
  temporaryFilename: "string" # see below. default: nil
, successCallback, errorCallback

successCallback: ({
  photoUrl,
  pixelWidth,
  pixelHeight,
  originalPixelWidth,
  originalPixelHeight
}) ->
```

```temporaryFilename```

If the name is the same as a previous call, the previous image is overwritten. This is handy so you don't end up with lots of temporary files wasting the users's storage.

#### photoAssetsChanged event

```coffeescript
document.addEventListener 'photoAssetsChanged', ({details})->
  {options, collections, assets} = details

  {currentCollectionKey, offset, limit} = options

  currentCollection = collections[currentCollectionKey]
  {collectionKey, collectionName, estimatedAssetCount} = currentCollection

  [{
    assetKey
    thumbnailUrl
    thumbnailPixelWidth
    thumbnailPixelHeight
    originalPixelWidth
    originalPixelHeight
    creationDate
    modificationDate
  }] = assets
```

The event object's ```details```:

* collections: same object returned by getCollections
* options: same object returned by getOptions
* assets: an array of assets. assets.length <= limit

The asset objects have the following fields:

* assetKey: unique identifier for the asset. Required for ```getPhoto```.
  * Ex use: ```PhotoAssets.getPhoto assetKey: assetKey```.
* thumbnailUrl: the URL of the immediately-available copy of the thumbnail for this asset
* thumbnailPixelWidth, thumbnailPixelHeight: size of the thumbnail image
* originalPixelWidth, originalPixelHeight: size of the original image
* creationDate: string
* modificationDate: string

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
