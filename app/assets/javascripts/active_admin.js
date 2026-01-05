// Active Admin JavaScript
// This file is required by Active Admin for proper functionality

// Basic JavaScript for Active Admin
$(document).ready(function() {
  console.log("Active Admin loaded");
  
  // Add any custom Active Admin JavaScript here
  
  // Example: Handle form submissions
  $('.formtastic form').on('submit', function() {
    // Add any custom form handling
  });
  
  // Example: Handle table row clicks
  $('.index_table tbody tr').on('click', function(e) {
    if (!$(e.target).is('a, input, button')) {
      var link = $(this).find('a').first();
      if (link.length) {
        window.location = link.attr('href');
      }
    }
  });
});
