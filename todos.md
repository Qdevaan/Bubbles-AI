# Bubbles AI Project Roadmap

## 🎭 Roleplay Mode
- [x] **Character Consistency**: Ensure AI never breaks character (avoid "As an AI..." or "As a large language model...").
- [ ] **Engaging Interactions**: Make conversations feel natural and engaging, like talking to a real person.
- [x **User-Specific Entities**: Only display entities that are relevant to the current user.

## 📜 History & Search
- [x] **Chronological Order**: Display live session history in reverse chronological order, with a toggle to switch sorting direction.
- [x] **Grammar & Flow**: Ensure history shows complete, proper sentences rather than fragments.
- [x] **AI Response Visibility**: Show all AI responses in the history logs.
- [x] **Selection Highlights**: Highlight the specific AI responses that the user selected during the session.
- [x] **Search Functionality**: Add a search tab to the history screen for searching through chat history.
- [x] **Tabbed Interface**: Implement a tab-based layout for better navigation.
- [x] **Dual History Tabs**: Switch between 'Live Session History' and 'Conversation History' (including roleplay sessions).
- [x] **AI-Generated Naming**: Use AI to automatically name conversations in the history list.

## 💬 Chat Sessions
- [x] **Auto-Titles**: Use AI to generate descriptive titles for each chat session.
- [x] **Session Summaries**: Generate AI summaries for every session.
- [x] **Key Points Extraction**: Use AI to list the main takeaways from each session.
- [x] **Shareability**: Implement functionality to share chat sessions.
- [x] **Context Isolation**: Each session should feel fresh; do not reference past chats unless explicitly asked.
- [x] **Conversation Modes**: Support three distinct modes: **Formal**, **Semi-Formal**, and **Informal**.
- [x] **Prompt Engineering**: Rewrite server v2 AI prompts to strictly adhere to the selected mode.
- [x] **Mode Selection UI**: Allow users to select their preferred mode before starting a new chat session.
- [x] **Persistent Mode Indicator**: Display the active conversation mode clearly in the chat interface.
- [x] **Selection Strategy**: Prompt for mode on every new session, with an option to "Set as default for all sessions" (changeable in settings).
- [x] **Redesign Chat Screen UI**: The current UI of the chat screen is not user-friendly. Redesign it to make it more user-friendly and visually appealing. Just like GPT mobile interface.

## 🧩 Entities & Management
- [x] **Unified Extraction**: Extract entities from both Live and Consultation modes.
- [x] **Entity Organization**: Group entities logically on the entities screen with an easy-to-understand UI.
- [x] **Entity Search**: Add a search bar to filter through extracted entities.
- [x] **Categorization**: Group entities into major categories (Person, Location, Organization, Event, etc.).
- [x] **Contextual Links**: Make entities clickable to show all related conversations.
- [x] **Entity Metadata**: Display key points and summaries specifically related to each entity.
- [x] **CRUD Operations**: Allow users to edit and delete entities.
- [x] **Relationship Mapping**: Show a list of other entities related to the selected one.

## 🕸️ Knowledge Graph & Query Engine
- [x] **Graph Visualization**: Implement a visual representation of all entities and their relationships.
- [x] **Quick References**: Clicking an entity in the graph shows AI summary and related points (node tap → bottom sheet).
- [x] **Graph Query Engine**: Floating search bar answers natural language questions about the graph (e.g., "Who is Ali?").
- [x] **Relationship Deep-Dive**: Make relationship links clickable to view associated conversations.

## 🎙️ Live Session
- [x] **UI Redesign**: Perform a complete redesign of the live session interface.
- [x] **Immediate Feedback**: Show AI responses immediately during the session.
- [x] **Graph Pre-loading**: Download the knowledge graph into RAM before starting and sync updates at the end.
- [x] **Post-Session Insights**: Automatically generate and show summaries, key points, and entities immediately after a session ends.
- [x] **Live Session Modes**: Support **Formal**, **Semi-Formal**, and **Informal** modes for live coaching.
- [x] **Dynamic Switching**: Allow users to switch modes *during* a live session and update the AI prompt accordingly.
- [x] **Selection Strategy**: Prompt for mode on every new live session, with an option to "Set as default" (changeable in settings).

## 🎮 Gamification & Game Mode
- [x] **Adaptive Missions**: Generate daily missions based on mistakes or weak areas identified in live sessions.
- [x] **Mission Variety**: Missions can consist of specific conversations or sets of questions.
- [x] **Reward System**: Assign points to missions that can be used to unlock rewards.
- [x] **Retention Mechanics**: Implement daily streaks and bonus points for consistent completion.
- [x] **Competitive Play**: Create leaderboards for user competition.
- [x] **Performance Metrics**: Implement a points system based on overall user performance.
- [x] **Milestones**: Add achievements for reaching specific milestones and maintaining streaks.

## 🔧 Performance Optimization :
- [x] **Prompt Optimization**: Refine and shorten prompts to reduce LLM latency and token costs.
- [x] **API Efficiency**: Optimize backend API calls and payload sizes to reduce response times.
- [x] **UI Responsiveness**: Optimize Flutter rendering and state management to ensure a lag-free experience.
- [x] **Auto Reload**: when app connects to the server, automatically update all screens and their relevent data and keep them in cache, game related, graphs, chats, summries or orher, automatically fetch them and store them in cache
- [x] **Supabase Update**: update everything on supabase, and our app fetches most of the data from supabase which doesent require an active server connection, like game related features or others, flutter app auto receives that from database and and also updates them on completetion.
- [x] **Store Everythingh**: Store Everything on supabase, every little or minute details directly, and make it so we fetch it from supabase, unless it is time critical, that directly comes from server like live session, but everything is still recorded on supabase.
- [x] **New Prompts**: write new detailed and specific prompts to cover all of the live sessions modes and as well as consultant session mods and roleplay mods, in live session, prompt should be for suggestions from past convos using RAG and Network X graphs, work as an assistant, that silently hand overs important key points to the user and aids them in the conve, while in Consultan mode, the AI prompt should be so it acts like a professional consultant, that has all your details, background knowledge and everything, and helps you in any way possible, while in role play model, the prompt is created on the run, about the details we have about the entity, and we currate a promt according to that entity, and the AI model tries to mimic that entity in the role play model. Write the prompts and services accordingly.

## ⚙️ Notifications
- [x] **Intelligent Alerts**: Show notifications for important events, dates, and deadlines extracted from sessions.
- [x] **Feature Announcements**: Notify users when new gamification features or rewards become available.
- [x] **Notification Settings**: Allow users to enable/disable specific notification types in the settings menu.
- [x] **Push Support**: Implement native push notifications for all platforms.

## ✨ Recent Insights (Home Screen)
- [x] **Contextual Home Feed**: Display recent insights directly on the home screen.
- [x] **Dismissible Cards**: Insights are dismissible with swipe-left gesture (optimistic removal + Supabase persistence).
- [x] **Visual Overhaul**: Design a premium carousel or list of cards for insights.
- [x] **Deep Linking**: Make insights clickable to jump directly to the source conversation.
- [x] **Real-Time Updates**: Ensure new insights appear on the home screen instantly upon generation.

## ⚡ Quick Actions
- [x] **Contextual Icons**: Replaced generic icons with specific, meaningful icons (`history_rounded`, `psychology_rounded`).
- [x] **Customizable Shortcuts**: Allow users to select which actions they want to see in their quick actions bar.

## 🚀 Future / "If Possible"
- [ ] **Gemma 4 Integration**: Research and implement Google's Gemma 4 model for improved local/server performance.
- [ ] **Offline Retrieval**: Enable querying of cached data and local knowledge graph using local Gemma 4 without internet.
- [ ] **Multimodal Local LLM**: Add image support to the local model to answer questions about visual inputs.
