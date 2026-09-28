# Database Preparing for project
Because of Copyright.. the Database has been removed from the GIT
You may find it here: https://drive.google.com/drive/folders/1UI5kI4RdDnGNouPEwEVqu-xOPkrmFuRh?usp=sharing

The File may be mixed copyright and will have a "license" table describing the tables for the different data copyrights which are mostly creative commons nc or the pali data from vri which they claimed as copyright material even though it is public domain from the 6th Buddhist Council.
Some tables may be mixed and copyrighted by field codes (which describe the book name in the dictionary, etc)
Other dictionaries may also be copyrighted and are used with permission or permission is beign sought during the development stages.
Never the less, all are distributed as free and not commerical material and technicalities might need to be worked out.



## Problem with large assets file copy
rootBundle.load method loads all content of

[flutter issues](https://github.com/flutter/flutter/issues/26465)
## To megre part files to db file

```
cat tipitaka_pali_part.* > tipitaka_pali.db
```

## delete all part files

```
rm tipitaka_pali_part.*
```

## To split the files again type this:
(period at end is important)

```
split -b 50000k tipitaka_pali.db tipitaka_pali_part.
```

# The sentence databases

Three databases ship in this folder, none of them in git. The Pali one is the
same as it has always been, from the Drive link above. The other two are new
and are produced from it, so there is nothing to download for them.

| file | parts | size | where it comes from |
| --- | --- | --- | --- |
| `tipitaka_pali.db` | 14 | 656 MB | the Drive link above |
| `epitaka.db` | 5 | 210 MB | built from an ePitaka release |
| `tpr_extension.db` | 1 | 22 MB | built from the two above |

## epitaka.db

Download `epitaka.zip` from the ePitaka releases, unzip it, then trim it to the
tables TPR reads. The published file is 578 MB and most of that is dictionaries
and embeddings the app never touches.

```
python tools/epitaka_migration/build_shipping_db.py --source epitaka.db --out epitaka_ship.db
```

## tpr_extension.db

This is TPR's own: the page boundaries, the page markers for all four printed
editions, and the orphan flags, all keyed the way ePitaka keys its sentences.
It is produced by running the pipeline in `tools/epitaka_migration/` against
the original `tipitaka_pali.db` and the untrimmed `epitaka.db`. See the README
there; it takes about an hour, most of it in the matching step.

Note it must be rebuilt whenever a newer ePitaka release is used, because the
positions it stores are offsets into ePitaka's sentences.

## Splitting and merging

Put `epitaka.db` and `tpr_extension.db` in this folder and run:

```
bash split_epitaka.sh
```

To work on them again, `bash merge_epitaka.sh` puts them back together. If the
number of parts changes, update `pubspec.yaml` and `AssetsFile` in
`lib/data/constants.dart` to match.

## Translations

Not shipped. A reader chooses one at first start, or later in settings, and it
is downloaded and trimmed to the sentences alone on the device.
