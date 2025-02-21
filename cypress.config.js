const { defineConfig } = require("cypress");

module.exports = defineConfig({
  e2e: {
    projectId: 'qsvn1w',  // Add your project ID here
    setupNodeEvents(on, config) {
      // implement node event listeners here
    },
  },
});
