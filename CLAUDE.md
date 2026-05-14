# fogworld

## Design Principles

### Raw Data Preservation
実際の緯度経度情報（RecordedPoint）は絶対に捨てない。描画の最適化（LOD、マージ、フィルタ）は描画レイヤーでのみ行い、保存されたrawデータには手を加えない。
