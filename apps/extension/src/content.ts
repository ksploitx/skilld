// content script
const checkInputBox = () => {
  // Basic check for claude's input box (this selector might need to be adjusted)
  const inputBox = document.querySelector('div[contenteditable="true"]');
  if (inputBox) {
    console.log("skilld loaded");
  }
};

// Run on load and observe DOM changes if necessary
window.addEventListener('load', checkInputBox);
