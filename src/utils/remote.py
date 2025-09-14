def download_file(url: str, dest_path: str, dest_filename: str) -> str:
    import requests
    import os
    
    try:
        response = requests.get(url, stream=True)
        response.raise_for_status()
        file_ext = response.headers.get('Content-Type', '').split('/')[-1]
        
        if file_ext == '' or file_ext not in ['octet-stream', 'x-wav', 'mpeg', 'mp3', 'wav', 'mp4', 'quicktime', 'x-m4a']:
            raise ValueError(f"Unsupported file type: {file_ext}")
        
        dest_filename += f".{file_ext}"
        os.makedirs(dest_path, exist_ok=True)
        dest_path = os.path.join(dest_path, dest_filename)
        with open(dest_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        return dest_path
    except Exception as e:
        raise RuntimeError(f"Failed to download file from {url}: {e}")