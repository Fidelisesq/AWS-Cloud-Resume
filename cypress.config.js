const { defineConfig } = require("cypress");

module.exports = defineConfig({
  e2e: {
    projectId: 'qsvn1w',  // Add your project ID here
    specPattern: 'cypress/e2e/**/*.cy.{js,jsx,ts,tsx}',
    setupNodeEvents(on, config) {
      // implement node event listeners here
    },
  },
});
