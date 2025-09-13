from abc import ABC, abstractmethod

class ModelWrapper(ABC):
    def __init__(self, model_name):
        self.model_name = model_name
        
    @abstractmethod
    def load_model(self):
        pass
    
    @abstractmethod
    def predict(self, input_data):
        pass