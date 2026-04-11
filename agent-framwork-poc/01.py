import asyncio
import os
from typing import Annotated
from pydantic import Field
from dotenv import load_dotenv
from agent_framework import AgentThread, ChatAgent
from agent_framework.azure import AzureAIAgentClient
from azure.identity.aio import DefaultAzureCredential
from azure.identity.aio import AzureCliCredential

# Load environment variables from .env file
load_dotenv()

def get_weather(
    location: Annotated[str, Field(description="The location to get the weather for.")],
) -> str:
    """Get the weather for a given location."""
    return f"The weather in {location} is sunny with a high of 25°C."

async def main():
    """Main async function."""
    
    # Get Azure AI Foundry configuration from environment variables
    # You need Azure AI Foundry project endpoint (not Azure OpenAI endpoint)
    # Get from: https://ai.azure.com -> Your Project -> Settings -> Connection String
    azure_ai_project_endpoint = os.getenv("AZURE_AI_PROJECT_ENDPOINT")
    model = os.getenv("AZURE_OPENAI_MODEL", "gpt-4o")
    
    if not azure_ai_project_endpoint:
        print("❌ Error: AZURE_AI_PROJECT_ENDPOINT not set!")
        print("\nTo use AzureAIAgentClient, you need an Azure AI Foundry project.")
        print("\nSteps:")
        print("1. Go to https://ai.azure.com")
        print("2. Create a new project (or select existing)")
        print("3. Go to Settings -> Get connection string")
        print("4. Add to .env file:")
        print('   AZURE_AI_PROJECT_ENDPOINT="https://your-project.eastus.api.azureml.ms"')
        print("\nNote: This is different from Azure OpenAI endpoint (.cognitiveservices.azure.com)")
        return
    
    print(f"✓ Configuration loaded")
    print(f"  Azure AI Project Endpoint: {azure_ai_project_endpoint}")
    print(f"  Model: {model}\n")
    
    # Create a ChatAgent with Azure AI Foundry client
    async with (
        AzureCliCredential() as credential,
        ChatAgent(
            chat_client=AzureAIAgentClient(
                async_credential=credential,
                project_endpoint=azure_ai_project_endpoint,
                model_deployment_name=model
            ),
            instructions="You are a helpful weather agent.",
            tools=get_weather,
        ) as agent,
    ):
        # Agent is now ready to use
        
        # Create the agent thread for ongoing conversation
        thread = agent.get_new_thread()
        
        # Ask questions and get responses
        first_query = "What's the weather like in Seattle?"
        print(f"User: {first_query}")
        first_result = await agent.run(first_query, thread=thread)
        print(f"Agent: {first_result.text}")

if __name__ == "__main__":
    asyncio.run(main())