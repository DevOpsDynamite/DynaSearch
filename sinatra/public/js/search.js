// File: DynaSearch/sinatra/public/js/search.js

/**
 * Reads the search input value and reloads the page
 * with the query parameter updated.
 */
function makeSearchRequest() {
    // Find the input element reliably within the function
    const searchInput = document.getElementById("search-input");
    // Proceed only if the input element exists
    if (searchInput) {
      const query = searchInput.value;
      const url = new URL(window.location.href);
      url.searchParams.set('q', query);
      window.location.href = url.toString();
    } else {
      console.error("Search input element not found.");
    }
  }
  
  /**
   * Sets up event listeners once the page content is loaded.
   */
  document.addEventListener('DOMContentLoaded', () => {
    const searchInput = document.getElementById("search-input");
    const searchButton = document.getElementById("search-button");
  
    // Ensure the search input exists before trying to use it
    if (searchInput) {
      // Focus the input field automatically
      searchInput.focus();
  
      // Add event listener for the Enter key in the search input
      searchInput.addEventListener('keypress', (event) => {
        // Check if the key pressed was Enter
        if (event.key === 'Enter') {
          // Prevent the default Enter key action (like form submission, if it were in a form)
          event.preventDefault();
          // Trigger the search function
          makeSearchRequest();
        }
      });
    } else {
      console.warn("Search input element (#search-input) not found on this page.");
    }
  
    // Ensure the search button exists before adding a listener
    if (searchButton) {
      // Add event listener for clicks on the search button
      searchButton.addEventListener('click', (event) => {
         // Prevent default button action (like form submission)
        event.preventDefault();
        // Trigger the search function
        makeSearchRequest();
      });
    } else {
      console.warn("Search button element (#search-button) not found on this page.");
    }
  });