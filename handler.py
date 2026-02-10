import runpod
import json
import base64
import time
import urllib.request
import urllib.parse
import urllib.error
import uuid
import os
import random
import logging
import websocket

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration
SERVER_ADDRESS = os.getenv('SERVER_ADDRESS', '127.0.0.1')
COMFY_API_URL = f"http://{SERVER_ADDRESS}:8188"
WORKFLOW_PATH = "/workflow_api.json"


def queue_prompt(prompt, client_id=None):
    """Submit a workflow to ComfyUI via HTTP POST."""
    payload = {"prompt": prompt}
    if client_id:
        payload["client_id"] = client_id
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(f"{COMFY_API_URL}/prompt", data=data, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        error_body = ""
        try:
            error_body = e.read().decode('utf-8')
        except Exception:
            pass
        logger.error(f"Failed to queue prompt: HTTP {e.code} - {error_body}")
        raise RuntimeError(f"ComfyUI rejected workflow (HTTP {e.code}): {error_body[:500]}")
    except urllib.error.URLError as e:
        logger.error(f"Failed to queue prompt: {e}")
        raise


def get_history(prompt_id):
    """Retrieve workflow execution history from ComfyUI."""
    req = urllib.request.Request(f"{COMFY_API_URL}/history/{prompt_id}")
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.URLError as e:
        logger.error(f"Failed to get history: {e}")
        raise


def get_video(ws, prompt):
    """Wait for workflow completion via WebSocket and retrieve output video."""
    prompt_id = prompt['prompt_id']
    logger.info(f"Waiting for prompt completion: {prompt_id}")

    while True:
        try:
            out = ws.recv()
            if isinstance(out, str):
                message = json.loads(out)
                if message['type'] == 'executing':
                    data = message['data']
                    if data['node'] is None and data['prompt_id'] == prompt_id:
                        logger.info("Execution complete")
                        break
            else:
                continue
        except Exception as e:
            logger.error(f"WebSocket receive error: {e}")
            raise

    # Get video from history
    history = get_history(prompt_id)[prompt_id]

    if 'status' in history and history['status'].get('status_str') == 'error':
        error_msgs = history['status'].get('messages', [])
        raise RuntimeError(f"ComfyUI workflow failed: {error_msgs}")

    outputs = history.get('outputs', {})

    # SaveVideo (node 75) outputs videos
    # Check all keys in the output (could be 'gifs', 'videos', or others)
    logger.info(f"Expecting video output from node 75 (SaveVideo)")
    for node_id, node_output in outputs.items():
        # Iterate all possible output keys
        for output_key in node_output.keys():
            if isinstance(node_output[output_key], list):
                for item in node_output[output_key]:
                    if isinstance(item, dict) and 'filename' in item:
                        # Build URL parameters for video retrieval
                        params = {
                            'filename': item['filename'],
                            'type': item.get('type', 'output')
                        }
                        if 'subfolder' in item and item['subfolder']:
                            params['subfolder'] = item['subfolder']

                        # Retrieve video via HTTP
                        url = f"{COMFY_API_URL}/view?{urllib.parse.urlencode(params)}"
                        req = urllib.request.Request(url)
                        with urllib.request.urlopen(req, timeout=60) as response:
                            video_data = response.read()
                            logger.info(f"Retrieved video: {item['filename']} ({len(video_data)} bytes)")
                            return video_data

    raise RuntimeError("No video output found in workflow results")


def load_workflow(path):
    """Load workflow JSON from file."""
    with open(path, 'r') as f:
        return json.load(f)


def wait_for_comfyui_http(timeout=300):
    """Wait for ComfyUI HTTP endpoint to be ready."""
    logger.info(f"Waiting for ComfyUI at {COMFY_API_URL}...")
    start_time = time.time()
    attempts = 0
    max_attempts = timeout

    while attempts < max_attempts:
        try:
            req = urllib.request.Request(f"{COMFY_API_URL}/system_stats")
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    logger.info("ComfyUI HTTP is ready!")
                    return True
        except (urllib.error.URLError, urllib.error.HTTPError):
            pass

        attempts += 1
        time.sleep(1)

        if attempts % 30 == 0:
            logger.info(f"Still waiting for ComfyUI... ({attempts}/{max_attempts})")

    raise TimeoutError(f"ComfyUI did not become ready within {timeout} seconds")


def connect_websocket_with_retry(max_attempts=36, retry_delay=5):
    """Connect to ComfyUI WebSocket with retry logic. Returns (ws, client_id)."""
    client_id = str(uuid.uuid4())
    ws_url = f"ws://{SERVER_ADDRESS}:8188/ws?clientId={client_id}"

    for attempt in range(max_attempts):
        try:
            logger.info(f"Attempting WebSocket connection (attempt {attempt + 1}/{max_attempts})")
            ws = websocket.create_connection(ws_url, timeout=1200)
            logger.info(f"WebSocket connected successfully (clientId={client_id})")
            return ws, client_id
        except Exception as e:
            logger.warning(f"WebSocket connection failed: {e}")
            if attempt < max_attempts - 1:
                time.sleep(retry_delay)
            else:
                raise RuntimeError(f"Failed to connect to WebSocket after {max_attempts} attempts")


def handler(job):
    """Main handler for LTX-2 Text-to-Video workflow (2-stage pipeline with 92:XX subgraph nodes)."""
    task_id = str(uuid.uuid4())
    ws = None

    try:
        job_input = job.get("input", {})

        # Extract parameters
        prompt = job_input.get("prompt")
        aspect_ratio = job_input.get("aspect_ratio", "16:9")

        if not prompt:
            return {"error": "Missing required parameter: prompt"}

        # Validate and map aspect_ratio
        ASPECT_RATIO_MAP = {
            "16:9": (1280, 720),
            "9:16": (720, 1280),
        }
        if aspect_ratio not in ASPECT_RATIO_MAP:
            return {"error": f"Invalid aspect_ratio: {aspect_ratio}. Must be '16:9' or '9:16'"}
        width, height = ASPECT_RATIO_MAP[aspect_ratio]

        # Internal defaults (not exposed to API)
        frame_count = 121
        seed = 0

        logger.info(f"Task {task_id}: Processing text-to-video with prompt: '{prompt[:80]}...'")
        logger.info(f"Parameters - aspect_ratio: {aspect_ratio}, width: {width}, height: {height}, frame_count: {frame_count}")

        # Handle seed
        if seed == 0 or seed == -1:
            seed = random.randint(0, 2**53)
        logger.info(f"Using seed: {seed}")

        # Load workflow
        workflow = load_workflow(WORKFLOW_PATH)

        # Inject parameters into workflow nodes (92:XX subgraph format)
        # Stage 1 - positive prompt
        workflow["92:3"]["inputs"]["text"] = prompt
        # Stage 1 & 2 seeds
        workflow["92:11"]["inputs"]["noise_seed"] = seed
        workflow["92:67"]["inputs"]["noise_seed"] = seed
        # Resolution (EmptyImage feeds into size calculation chain)
        workflow["92:89"]["inputs"]["width"] = width
        workflow["92:89"]["inputs"]["height"] = height
        # Frame count
        workflow["92:43"]["inputs"]["length"] = frame_count
        workflow["92:51"]["inputs"]["frames_number"] = frame_count

        # Wait for ComfyUI HTTP endpoint
        wait_for_comfyui_http(timeout=300)

        # Connect WebSocket
        ws, client_id = connect_websocket_with_retry(max_attempts=36, retry_delay=5)

        # Queue workflow
        logger.info("Submitting workflow to ComfyUI...")
        prompt_response = queue_prompt(workflow, client_id=client_id)
        prompt_id = prompt_response.get('prompt_id')

        if not prompt_id:
            return {"error": "Failed to get prompt_id from ComfyUI"}

        logger.info(f"Workflow queued with prompt_id: {prompt_id}")

        # Wait for completion and get video
        video_data = get_video(ws, {'prompt_id': prompt_id})

        # Close WebSocket
        ws.close()
        ws = None

        # Calculate duration (assuming 24 fps)
        duration_seconds = frame_count / 24.0

        result_b64 = base64.b64encode(video_data).decode('utf-8')

        logger.info(f"Task {task_id}: Complete")

        return {
            "video": result_b64,
            "seed": seed,
            "prompt_id": prompt_id,
            "frame_count": frame_count,
            "duration_seconds": round(duration_seconds, 2)
        }

    except Exception as e:
        logger.error(f"Task {task_id} failed: {str(e)}", exc_info=True)
        return {"error": f"Processing failed: {str(e)}"}

    finally:
        # Cleanup
        if ws:
            try:
                ws.close()
            except Exception:
                pass


if __name__ == "__main__":
    wait_for_comfyui_http()
    runpod.serverless.start({"handler": handler})
