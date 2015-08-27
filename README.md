# cordova_photo_assets
Cordova Plugin for Accessing the Photo Assets on iOS and eventually Android

## API

### Simple Example

This example will list all assets for the first asset-collection found.

```coffeescript

document.addEventListener 'deviceready', ->
  PhotoAssets.setOptions currentAssetCollection: "all", ->
    console.log "all (local) photo assets selected, a photoAssetsChanged event will follow shortly"

document.addEventListener 'photoAssetsChanged', (photoAssets)->
  {collectionKey, collectionName, offset, limit, assets} = photoAssets

  console.log "#{collectionName} assets: #{offset} to #{offset + assets.length - 1}:"
  for asset in assets
    {
      pixelWidth, pixelHeight, thumbnailUrl, mediaType, creationDate,
      modificationDate, location, duration, favorite, hidden
    } = asset
    console.log "asset #{offset++}", asset

  if assets.length == limit
    PhotoAssets.setAssetWindow offset + limit, limit

```

### Extended Example

This example shows how to get a list of all available collections, how to follow one specifically, and how to set all custom options.

```coffeescript

document.addEventListener 'deviceready', ->

  PhotoAssets.getAssetCollections (assetCollections)->
    [{
      collectionKey
      collectionName
      estimatedAssetCount
      startDate
      endDate
      approximateLocation
      localizedLocationNames
    }] = assetCollections

    PhotoAssets.setOptions
      currentAssetCollection: collectionKey
      thumbnailSize: 270
      limit: 100
      offset: 0
      thumbnailQuality: 95
    , ->
      console.log "selected first asset collection: " + collectionName

```
