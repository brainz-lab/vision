# DiffService performs pixel-level comparison of two images using ImageMagick.
# Returns diff metrics and generates a visual diff image.

class DiffService
  attr_reader :image1_data, :image2_data, :options

  def initialize(image1_data, image2_data, options = {})
    @image1_data = image1_data
    @image2_data = image2_data
    @options = options
  end

  def diff
    # Create temporary files for ImageMagick comparison
    Dir.mktmpdir do |tmpdir|
      img1_path = File.join(tmpdir, 'image1.png')
      img2_path = File.join(tmpdir, 'image2.png')
      diff_path = File.join(tmpdir, 'diff.png')

      # Write images to temp files
      File.binwrite(img1_path, @image1_data)
      File.binwrite(img2_path, @image2_data)

      # Normalize dimensions if needed
      normalize_dimensions!(img1_path, img2_path)

      # Get image dimensions
      dimensions = get_dimensions(img1_path)
      total_pixels = dimensions[:width] * dimensions[:height]

      # Perform comparison using ImageMagick compare
      diff_pixels = perform_comparison(img1_path, img2_path, diff_path)

      # Read diff image
      diff_image_data = File.binread(diff_path) if File.exist?(diff_path)

      {
        diff_pixels: diff_pixels,
        diff_percentage: calculate_percentage(diff_pixels, total_pixels),
        diff_image: diff_image_data,
        match_percentage: 100 - calculate_percentage(diff_pixels, total_pixels),
        width: dimensions[:width],
        height: dimensions[:height]
      }
    end
  end

  private

  def normalize_dimensions!(img1_path, img2_path)
    dim1 = get_dimensions(img1_path)
    dim2 = get_dimensions(img2_path)

    return if dim1 == dim2

    # Resize both images to the larger dimensions
    max_width = [dim1[:width], dim2[:width]].max
    max_height = [dim1[:height], dim2[:height]].max

    resize_image(img1_path, max_width, max_height)
    resize_image(img2_path, max_width, max_height)
  end

  def get_dimensions(image_path)
    image = MiniMagick::Image.open(image_path)
    { width: image.width, height: image.height }
  end

  def resize_image(image_path, width, height)
    image = MiniMagick::Image.open(image_path)
    return if image.width == width && image.height == height

    image.resize("#{width}x#{height}!")
    image.write(image_path)
  end

  def perform_comparison(img1_path, img2_path, diff_path)
    # Use ImageMagick compare command
    # The compare command returns the number of different pixels
    # and generates a diff image highlighting the differences

    # Fuzz factor for color tolerance (0-100%)
    fuzz = options[:fuzz] || '5%'

    # Create a composite diff image
    MiniMagick::Tool::Compare.new do |compare|
      compare.metric('AE')  # Absolute Error count
      compare.fuzz(fuzz)
      compare.highlight_color('red')
      compare.lowlight_color('white')
      compare << img1_path
      compare << img2_path
      compare << diff_path
    end

    # Parse the diff pixel count from stderr (ImageMagick outputs it there)
    0  # Default, will be overwritten
  rescue MiniMagick::Error => e
    # ImageMagick compare returns non-zero exit when images differ
    # The error message contains the pixel count
    extract_diff_count(e.message)
  end

  def extract_diff_count(error_message)
    # ImageMagick outputs something like "12345" for the number of different pixels
    match = error_message.match(/(\d+)/)
    match ? match[1].to_i : 0
  end

  def calculate_percentage(diff_pixels, total_pixels)
    return 0.0 if total_pixels.zero?
    (diff_pixels.to_f / total_pixels * 100).round(4)
  end
end
