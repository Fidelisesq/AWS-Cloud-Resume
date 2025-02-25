// cypress/e2e/home.cy.js

describe('Resume Page', () => {
  beforeEach(() => {
    cy.visit('https://fidelis-resume.fozdigitalz.com'); // Visit the resume site
  });

  it('should contain my name', () => {
    cy.contains('Fidelis Ikoroje').should('be.visible'); // Checks for my name
  });

  it('should contain the PROFESSIONAL SUMMARY section', () => {
    cy.contains('PROFESSIONAL SUMMARY').should('be.visible');
  });

  it('should contain the PERSONAL PROJECT EXPERIENCE/LEARNING section', () => {
    cy.contains('PERSONAL PROJECT EXPERIENCE/LEARNING').should('be.visible');
  });

  it('should contain the Contacts like Email section', () => {
    cy.contains('fidelis.ikoroje@gmail.com').should('be.visible');
  });

  it('should navigate to GitHub when clicked', () => {
    cy.get('a[href="https://github.com/Fidelisesq"]')
      .should('have.attr', 'target', '_blank')
      .and('have.attr', 'href', 'https://github.com/Fidelisesq');
  });

  it('should navigate to LinkedIn when clicked', () => {
    cy.get('a[href="https://www.linkedin.com/in/fidelis-ikoroje/"]')
      .should('have.attr', 'target', '_blank')
      .and('have.attr', 'href', 'https://www.linkedin.com/in/fidelis-ikoroje/');
  });

  it('should navigate to Blog when clicked', () => {
    cy.get('a[href="https://dev.to/fidelisesq"]')
      .should('have.attr', 'target', '_blank')
      .and('have.attr', 'href', 'https://dev.to/fidelisesq');
  });

  it('should display a non-zero visitor count', () => {
    // Log the initial state of the visitor count
    cy.get('#visitor-counter').then(($el) => {
      console.log('Initial Visitor Count:', $el.text());
    });

    // Wait for the visitor count to update
    cy.get('#visitor-counter', { timeout: 20000 }) // Wait up to 20 seconds
      .should('be.visible')
      .and('not.contain', 'Visitor Count: 0') // Wait until the count is no longer 0
      .invoke('text')
      .then((text) => {
        console.log('Updated Visitor Count:', text); // Log the updated text
        const visitorCount = text.replace(/\D/g, ''); // Extract digits
        const count = parseInt(visitorCount);
        expect(count).to.be.greaterThan(0); // Ensure the count is greater than 0
      });
  });

  it('should display no broken images on the page', () => {
    cy.get('img').each(($img) => {
      cy.wrap($img)
        .should('be.visible')
        .and('have.prop', 'naturalWidth')
        .and('be.greaterThan', 0); // Ensure images are not broken
    });
  });
});