//= require rails-ujs
//= require active_admin/base
//= require arctic_admin/base

// Active Admin JavaScript
$(document).ready(function() {
  var $body = $("body");
  var $header = $("#header");
  var $tabs = $("#tabs");

  $body.addClass("aa-page-enter");
  setTimeout(function() {
    $body.addClass("aa-page-enter-active");
  }, 20);

  if ($tabs.length && $header.length) {
    // Create toggle button if it doesn't exist
    if (!$(".aa-sidebar-toggle").length) {
      $header.prepend(
        '<button type="button" class="aa-sidebar-toggle" aria-label="Toggle sidebar"><i class="fa-solid fa-bars"></i></button>'
      );
    }

    // Create overlay for mobile
    if (!$(".aa-sidebar-overlay").length) {
      $body.append('<div class="aa-sidebar-overlay"></div>');
    }

    // Desktop should always stay expanded.
    if (window.innerWidth > 1024) {
      $body.removeClass("aa-sidebar-collapsed");
      localStorage.removeItem("aa-sidebar-collapsed");
    }

    // Toggle sidebar collapse/expand
    $(".aa-sidebar-toggle").on("click", function(e) {
      e.preventDefault();
      e.stopPropagation();

      if (window.innerWidth <= 1024) {
        // Mobile/Tablet: toggle overlay
        $body.toggleClass("aa-sidebar-open");
      }
    });

    // Close sidebar on overlay click (mobile)
    $(".aa-sidebar-overlay").on("click", function() {
      $body.removeClass("aa-sidebar-open");
    });

    // Add data-label attributes for tooltips when collapsed
    $tabs.find("a").each(function() {
      var $link = $(this);
      var label = $link.text().trim();
      if (label && !$link.attr("data-label")) {
        $link.attr("data-label", label);
      }
    });

    // Close sidebar on menu item click (mobile)
    $tabs.find("a").on("click", function() {
      if (window.innerWidth <= 1024) {
        $body.removeClass("aa-sidebar-open");
      }
    });

    // Handle window resize
    $(window).on("resize", function() {
      if (window.innerWidth > 1024) {
        $body.removeClass("aa-sidebar-open");
        $body.removeClass("aa-sidebar-collapsed");
        localStorage.removeItem("aa-sidebar-collapsed");
      } else {
        // On mobile, remove collapsed class and use overlay mode
        $body.removeClass("aa-sidebar-collapsed");
      }
    });
  }
});
