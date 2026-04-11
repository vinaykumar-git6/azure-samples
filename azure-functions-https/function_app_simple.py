import azure.functions as func
import json

app = func.FunctionApp()

@app.function_name(name="health")
@app.route(route="health", auth_level=func.AuthLevel.ANONYMOUS)
def health(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps({"status": "healthy"}),
        mimetype="application/json",
        status_code=200
    )
