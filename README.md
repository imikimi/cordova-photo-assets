# cordova_photo_assets
Cordova Plugin for Accessing the Photo Assets on iOS and eventually Android

## API

### Simple Example

This example will list all assets for the first asset-collection found.

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

    PhotoAssets.selectAssetCollection collectionKey, ->
      console.log "selected first asset collection: " + collectionName

document.addEventListener 'photoAssetsChanged', (photoAssets)->
  {collectionKey, collectionName, offset, limit, assets} = photoAssets

  console.log "#{collectionName} assets: #{offset} to #{offset + assets.length - 1}:"
  for asset in assets
    {
      pixelWidth, pixelHeight, thumbnailUrl, mediaType, creationDate,
      modificationDate, location, diration, favorite, hidden
    } = asset
    console.log "asset #{offset++}", asset

  if assets.length == limit
    PhotoAssets.setAssetWindow offset + limit, limit

```
