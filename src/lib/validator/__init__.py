from pydantic import BaseModel
from typing import Dict, List

class PredictBody(BaseModel):
    input: Dict | List | str