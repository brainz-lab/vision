# frozen_string_literal: true

require "test_helper"

class DiffServiceTest < ActiveSupport::TestCase
  # ============================================
  # Helper Methods
  # ============================================

  # Create a simple PNG image with a solid color
  def create_test_image(width, height, color = "white")
    path = "/tmp/test_image_#{SecureRandom.hex(8)}.png"
    begin
      `convert -size #{width}x#{height} xc:#{color} #{path}`
      File.binread(path)
    ensure
      File.delete(path) if File.exist?(path)
    end
  end

  # Create an image with a colored rectangle (for creating differences)
  def create_image_with_rect(width, height, rect_x, rect_y, rect_w, rect_h, bg_color = "white", rect_color = "red")
    path = "/tmp/test_image_#{SecureRandom.hex(8)}.png"
    begin
      `convert -size #{width}x#{height} xc:#{bg_color} -fill #{rect_color} -draw "rectangle #{rect_x},#{rect_y} #{rect_x + rect_w},#{rect_y + rect_h}" #{path}`
      File.binread(path)
    ensure
      File.delete(path) if File.exist?(path)
    end
  end

  # ============================================
  # Initialization
  # ============================================

  test "initializes with two images" do
    image1 = create_test_image(100, 100)
    image2 = create_test_image(100, 100)

    service = DiffService.new(image1, image2)

    assert_equal image1, service.image1_data
    assert_equal image2, service.image2_data
  end

  test "initializes with options" do
    image1 = create_test_image(100, 100)
    image2 = create_test_image(100, 100)
    options = { fuzz: "10%" }

    service = DiffService.new(image1, image2, options)

    assert_equal options, service.options
  end

  # ============================================
  # Diff - Identical Images
  # ============================================

  test "diff returns 0 difference for identical images" do
    image = create_test_image(100, 100, "white")

    service = DiffService.new(image, image)
    result = service.diff

    assert_equal 0, result[:diff_pixels]
    assert_equal 0.0, result[:diff_percentage]
    assert_equal 100.0, result[:match_percentage]
    assert_equal 100, result[:width]
    assert_equal 100, result[:height]
  end

  test "diff generates diff_image" do
    image1 = create_test_image(100, 100, "white")
    image2 = create_image_with_rect(100, 100, 10, 10, 20, 20, "white", "red")

    service = DiffService.new(image1, image2)
    result = service.diff

    assert_not_nil result[:diff_image]
    assert result[:diff_image].bytesize > 0
  end

  # ============================================
  # Diff - Different Images
  # ============================================

  test "diff detects differences between images" do
    image1 = create_test_image(100, 100, "white")
    image2 = create_image_with_rect(100, 100, 0, 0, 50, 50, "white", "black")

    service = DiffService.new(image1, image2)
    result = service.diff

    # Should detect ~25% difference (50x50 out of 100x100)
    assert result[:diff_pixels] > 0
    assert result[:diff_percentage] > 0
    assert result[:match_percentage] < 100
  end

  test "diff returns higher percentage for more different images" do
    image1 = create_test_image(100, 100, "white")

    # Small difference
    image_small_diff = create_image_with_rect(100, 100, 0, 0, 10, 10, "white", "black")
    small_result = DiffService.new(image1, image_small_diff).diff

    # Large difference
    image_large_diff = create_image_with_rect(100, 100, 0, 0, 80, 80, "white", "black")
    large_result = DiffService.new(image1, image_large_diff).diff

    assert large_result[:diff_percentage] > small_result[:diff_percentage]
    assert large_result[:diff_pixels] > small_result[:diff_pixels]
  end

  # ============================================
  # Dimension Handling
  # ============================================

  test "diff handles images with different dimensions" do
    image1 = create_test_image(100, 100, "white")
    image2 = create_test_image(150, 120, "white")

    service = DiffService.new(image1, image2)
    result = service.diff

    # Images should be normalized to the larger dimensions
    assert_equal 150, result[:width]
    assert_equal 120, result[:height]
  end

  test "diff normalizes images to maximum dimensions" do
    small = create_test_image(50, 50, "white")
    large = create_test_image(100, 100, "white")

    service = DiffService.new(small, large)
    result = service.diff

    assert_equal 100, result[:width]
    assert_equal 100, result[:height]
  end

  # ============================================
  # Fuzz Option
  # ============================================

  test "diff respects fuzz option for color tolerance" do
    # Create two slightly different images
    image1 = create_test_image(100, 100, "#FFFFFF")
    image2 = create_test_image(100, 100, "#FEFEFE")  # Very slight difference

    # Without fuzz (default 5%), small differences may still be detected
    result_default = DiffService.new(image1, image2).diff

    # With higher fuzz, more differences are tolerated
    result_high_fuzz = DiffService.new(image1, image2, { fuzz: "20%" }).diff

    # Higher fuzz should result in fewer detected differences
    # (or equal if already 0)
    assert result_high_fuzz[:diff_percentage] <= result_default[:diff_percentage]
  end

  # ============================================
  # Percentage Calculation
  # ============================================

  test "diff percentage calculation is accurate" do
    # 100x100 = 10,000 total pixels
    # 50x50 black rectangle = 2,500 different pixels
    # Expected: ~25% difference
    image1 = create_test_image(100, 100, "white")
    image2 = create_image_with_rect(100, 100, 0, 0, 50, 50, "white", "black")

    service = DiffService.new(image1, image2)
    result = service.diff

    # Allow some variance due to anti-aliasing and color tolerance
    assert result[:diff_percentage] > 20
    assert result[:diff_percentage] < 30
  end

  test "diff returns 0 percentage for identical images" do
    image = create_test_image(100, 100, "blue")

    service = DiffService.new(image, image)
    result = service.diff

    assert_equal 0.0, result[:diff_percentage]
    assert_equal 100.0, result[:match_percentage]
  end

  # ============================================
  # Edge Cases
  # ============================================

  test "diff handles very small images" do
    image1 = create_test_image(1, 1, "white")
    image2 = create_test_image(1, 1, "black")

    service = DiffService.new(image1, image2)
    result = service.diff

    assert_equal 1, result[:width]
    assert_equal 1, result[:height]
    # 1 pixel, 100% different
    assert_equal 100.0, result[:diff_percentage]
  end

  test "diff handles large images" do
    # This tests memory handling with larger images
    image1 = create_test_image(500, 500, "white")
    image2 = create_test_image(500, 500, "white")

    service = DiffService.new(image1, image2)
    result = service.diff

    assert_equal 500, result[:width]
    assert_equal 500, result[:height]
    assert_equal 0, result[:diff_pixels]
  end

  test "diff handles completely different images" do
    image1 = create_test_image(100, 100, "white")
    image2 = create_test_image(100, 100, "black")

    service = DiffService.new(image1, image2)
    result = service.diff

    # Should be 100% different
    assert_equal 100.0, result[:diff_percentage]
    assert_equal 0.0, result[:match_percentage]
    assert_equal 10_000, result[:diff_pixels]
  end

  # ============================================
  # Output Format
  # ============================================

  test "diff returns hash with expected keys" do
    image1 = create_test_image(100, 100)
    image2 = create_test_image(100, 100)

    service = DiffService.new(image1, image2)
    result = service.diff

    assert result.key?(:diff_pixels)
    assert result.key?(:diff_percentage)
    assert result.key?(:diff_image)
    assert result.key?(:match_percentage)
    assert result.key?(:width)
    assert result.key?(:height)
  end

  test "diff_percentage is rounded to 4 decimal places" do
    image1 = create_test_image(100, 100, "white")
    image2 = create_image_with_rect(100, 100, 0, 0, 33, 33, "white", "black")

    service = DiffService.new(image1, image2)
    result = service.diff

    # Check that percentage is a float with reasonable precision
    assert_kind_of Float, result[:diff_percentage]
    # Decimal places check
    decimal_places = result[:diff_percentage].to_s.split(".").last.length
    assert decimal_places <= 4
  end
end
