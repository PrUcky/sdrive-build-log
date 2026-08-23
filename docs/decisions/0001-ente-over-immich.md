# 0001: Ente over Immich

**Date:** 2026-08-23
**Status:** Accepted

## Context
When building a self-hosted Google Photos alternative, the immediate default choice in the community right now is Immich. Immich is incredible — it has a slick UI, massive community momentum, and heavily leverages server-side machine learning for things like facial recognition, object detection, and intelligent search. 

However, the core constraint of the `sdrive` project is absolute privacy and physical security. If someone steals the hardware from my living room, they should not be able to read my photos. 

## Decision
We will use **Ente** as the core software stack instead of Immich. 

Ente is built from the ground up for End-to-End Encryption (E2EE). The server component (`museum`) acts strictly as a dumb metadata router and permission granter. It never sees the raw photo bytes. All encryption, thumbnail generation, and metadata extraction happens entirely on the client (the mobile phone) before the data ever hits the network.

## Consequences
- **Positive:** We achieve mathematically guaranteed privacy against physical theft or server compromise.
- **Positive:** By pushing all compute-heavy tasks (ML, thumbnailing, transcoding) to the client, the server hardware requirements drop drastically.
- **Negative:** We lose the ability to do complex server-side search across the entire library (since the server cannot read the tags or image contents). We are constrained by the processing power of the mobile device for initial ingestion.