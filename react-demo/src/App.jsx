import { useState } from 'react';
import { CreateStory, EditorStory, CapitolAiWrapper, generateStory } from '@capitol.ai/react';

import './App.css';

function App() {
  const [currentStoryId, setCurrentStoryId] = useState();

  const handleCallback = async ({ storyId, promptInfo, setSourceIds, setIsSubmitLoading }) => {
    console.log('📢 [APP CALLBACK] Story creation requested with ID:', storyId);
    console.log('📢 [APP CALLBACK] Prompt info:', promptInfo);

    try {
      // Call generateStory to POST to /chat/async
      console.log('📢 [APP CALLBACK] Calling generateStory...');
      const response = await generateStory({
        storyId,
        userPrompt: promptInfo.text,
        storyPlanConfig: {}, // Using default config
        tags: [],
        sourceIds: [], // Backend will inject sources automatically
      });

      console.log('📢 [APP CALLBACK] generateStory response:', response);
      console.log('📢 [APP CALLBACK] Socket address from response:', response?.['socket-address'] || response?.socketAddress);

      // Switch to EditorStory
      console.log('📢 [APP CALLBACK] Switching to EditorStory component...');
      setCurrentStoryId(storyId);
    } catch (error) {
      console.error('❌ [APP CALLBACK] Error generating story:', error);
      setIsSubmitLoading(false);
    }
  };

  console.log('🔄 [APP RENDER] Current story ID:', currentStoryId);
  console.log('🔄 [APP RENDER] Rendering component:', currentStoryId ? 'EditorStory' : 'CreateStory');

  return (
    <CapitolAiWrapper>
      {!currentStoryId ? (
        <CreateStory callbackOnSubmit={handleCallback} />
      ) : (
        <EditorStory storyId={currentStoryId} />
      )}
    </CapitolAiWrapper>
  );
}

export default App;
