// cypress/e2e/home.cy.js

describe('Resume Page', () => {
    it('should visit the site and display the welcome message', () => {
      cy.visit('https://fidelis-resume.fozdigitalz.com'); // my resume site customain domain
      cy.contains('Fidelis Ikoroje');  // Checks for my name on the site
    });
  });
  