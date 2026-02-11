# T2V LTX2 Workflow - Deployment Complete

## Status
✅ **Workflow ACTIVE** - Successfully deployed and activated in n8n

## Deployment Details
- **Workflow ID**: `tqrmPp7oNO87pyZK`
- **Workflow Name**: `XiCON_T2V_LTX2_V1`
- **Status**: Active
- **n8n Instance**: https://vpsn8n.xicon.co.kr
- **Created**: 2026-02-10
- **Last Updated**: 2026-02-10
- **Nodes**: 20
- **Backup File**: `n8n_workflow_T2V_LTX2.json` (for reference/restore)

## Workflow Configuration

### Key Details
- **Name**: `XiCON_T2V_LTX2_V1`
- **Template ID**: `2ec171be-71e1-4a95-a28b-b533424ea98a` (in SQL query)
- **Webhook Path**: `ltx2_t2v`
- **RunPod Endpoint**: `2phnlzaiuyi5b1`
- **Wait Webhook ID**: `wait-t2v-ltx2`

### Input Parameters
```json
{
  "prompt": "Video generation prompt (text)",
  "width": 1280,
  "height": 720,
  "frame_count": 121,
  "seed": 0
}
```

### Output
- Video file (MP4, 1280x720)
- Stored in Supabase storage: `works/{user_id}/{work_id}/XiCON_T2V_{user_id}_{timestamp}.mp4`
- Database record in `files` table with video metadata

## Workflow Structure (Based on Dance SCAIL)

### Main Flow
1. **Webhook** (ltx2_t2v) → Receives generation request
2. **Execute SQL Query** → Fetch job from generation_jobs + works tables
3. **IF Jobs Exist** → Check if job exists
4. **Mark as Taken** → Update generation_jobs.status = 'taken'
5. **Build Payload** → Create RunPod input payload
6. **Submit to RunPod** → POST to RunPod endpoint
7. **Update Works to Processing** → Set works.status = 'processing'
8. **Wait Loop** → Poll RunPod status every 5s
9. **Switch (Status)** → Route based on COMPLETED/FAILED/CANCELLED
10. **Extract Video Data** → Parse base64 video from output
11. **Convert to File** → Convert base64 to binary
12. **Upload to Storage** → Upload to Supabase storage
13. **Create Files Record** → Insert into files table
14. **Prepare Update Data** → Prepare final work data
15. **Update Works to Completed** → Set works.status = 'completed'

### Error Handling
- **Failed** → Update works.status = 'failed'
- **Cancelled** → Update works.status = 'cancelled'
- **Loop** → If IN_QUEUE/IN_PROGRESS, preserve data and wait again

## Differences from Dance SCAIL Workflow

### Removed Components
- ❌ No thumbnail parsing (Dance SCAIL uses input image as thumbnail)
- ❌ No "Parse Thumbnail URL" node
- ❌ No "Create Thumbnail Record" node

### Modified Components
- ✅ Template ID: `2ec171be-71e1-4a95-a28b-b533424ea98a` (T2V LTX2)
- ✅ RunPod endpoint: `2phnlzaiuyi5b1`
- ✅ Input params: prompt-only (no image_url)
- ✅ Output video: 1280x720 (vs Dance 416x672)
- ✅ Webhook path: `ltx2_t2v` (vs `wan-scail-dance`)
- ✅ Wait webhook: `wait-t2v-ltx2` (vs `wait-dance-scail`)
- ✅ Filename: `XiCON_T2V_*.mp4` (vs `XiCON_Dance_*.mp4`)
- ✅ Frame count: 121 frames
- ✅ Tags: `{"T2V", "Text_to_Video", "AI생성"}`
- ✅ Title: "AI 생성 비디오"
- ✅ Model metadata: "LTX-2"

### Simplified Flow
```
T2V LTX2:
Webhook → Query → Build Payload → Submit → Wait → Extract → Upload → Create File → Complete

Dance SCAIL:
Webhook → Query → Build Payload → Submit → Wait → Extract → Upload → Create File → Parse Thumbnail → Create Thumbnail Record → Complete
```

## Next Steps

1. ✅ **Workflow Activated**: Already active in n8n
2. **Update Database Template**: Ensure `templates` table has workflow ID `tqrmPp7oNO87pyZK`
3. **Test the Workflow**: Create a test job via the frontend
4. **Monitor**: Check n8n executions for successful runs

## Database Template Record

You should have (or create) this in the `templates` table:
```sql
-- Check if exists
SELECT * FROM templates WHERE id = '2ec171be-71e1-4a95-a28b-b533424ea98a';

-- If not exists, create it
INSERT INTO templates (
  id,
  template_name,
  display_name,
  description,
  category,
  is_active,
  n8n_workflow_id,
  default_params
) VALUES (
  '2ec171be-71e1-4a95-a28b-b533424ea98a',
  'T2V_LTX2',
  'Text to Video (LTX-2)',
  'Generate cinematic videos from text prompts using LTX-2 model',
  'video_generation',
  true,
  'tqrmPp7oNO87pyZK',  -- Current workflow ID
  '{
    "prompt": "A beautiful cinematic video",
    "width": 1280,
    "height": 720,
    "frame_count": 121,
    "seed": 0
  }'::jsonb
);
```

## API Access

The n8n API is accessible with proper authentication:
- Use `X-N8N-API-KEY` header for authentication
- Activation endpoint: `POST /api/v1/workflows/{id}/activate`
- The workflow was successfully created and activated via API
