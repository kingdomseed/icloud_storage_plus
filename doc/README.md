# Documentation

This `doc/` folder contains a local export of the DeepWiki documentation for
this repository.

Source: https://deepwiki.com/kingdomseed/icloud_storage_plus

## Start here

- [Home](deepwiki/1_Home.md)
- [Getting Started](deepwiki/2_Getting_Started.md)
- [API Reference](deepwiki/3_API_Reference.md)

## Key topics

- [File transfer operations](deepwiki/4_File_Transfer_Operations.md)
- [In-place access operations](deepwiki/5_In-Place_Access_Operations.md)
- [Metadata operations](deepwiki/6_Metadata_Operations.md)
- [File management operations](deepwiki/7_File_Management_Operations.md)
- [Data models](deepwiki/8_Data_Models.md)
- [Error handling](deepwiki/9_Error_Handling.md)
- [Files app integration](deepwiki/25_Files_App_Integration.md)
- [Path validation and directory handling](deepwiki/26_Path_Validation_and_Directory_Handling.md)
- [Testing guide](deepwiki/27_Testing_Guide.md)

## Notes

- [Download flow rationale](notes/download_flow.md)
- [NSMetadataQuery notes](notes/nsmetadataquery.md)

## Regenerating the export

From the repo root:

```bash
deepwiki-export https://deepwiki.com/kingdomseed/icloud_storage_plus -o docs
```

Then move/rename the generated output directory to `doc/deepwiki/` if needed.

Finally, fix relative links in the generated pages (so repo file links work
from `doc/deepwiki/` on GitHub):

```bash
python3 scripts/fix_deepwiki_links.py
```
