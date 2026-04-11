import asyncio
import os
from typing import Annotated
from pydantic import Field
from dotenv import load_dotenv
from agent_framework import AgentThread, ChatAgent
from agent_framework.openai import OpenAIChatClient
from azure.identity.aio import DefaultAzureCredential

# Load environment variables from .env file
load_dotenv()

def get_weather(
    location: Annotated[str, Field(description="The location to get the weather for.")],
) -> str:
    """Get the weather for a given location."""
    return f"The weather in {location} is sunny with a high of 25°C."

async def main():
    """Main async function."""
    
    # Get Azure OpenAI configuration from environment variables
    azure_openai_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
    model = os.getenv("AZURE_OPENAI_MODEL", "gpt-4o")
    
    if not azure_openai_endpoint:
        print("❌ Error: AZURE_OPENAI_ENDPOINT not set!")
        return
    
    print(f"✓ Configuration loaded")
    print(f"  Azure OpenAI Endpoint: {azure_openai_endpoint}")
    print(f"  Model: {model}\n")
    
    # Create a ChatAgent with Azure OpenAI client
    async with (
        DefaultAzureCredential() as credential,
        ChatAgent(
            chat_client=OpenAIChatClient(
                async_credential=credential,
                azure_endpoint=azure_openai_endpoint,
                model=model
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
        
        # Continue the conversation
        second_query = "How about in Tokyo?"
        print(f"\nUser: {second_query}")
        second_result = await agent.run(second_query, thread=thread)
        print(f"Agent: {second_result.text}")

if __name__ == "__main__":
    asyncio.run(main())
