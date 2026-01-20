class PdfSignatureService
  def self.add_signature(unsigned_pdf_data, signature_image_path, coords)
    require 'prawn'
    require 'combine_pdf'

    # 1. Load the unsigned PDF
    pdf = CombinePDF.parse(unsigned_pdf_data)

    # 2. Create the signature layer using the passed 'coords'
    signature_layer = Prawn::Document.new(page_size: 'A4', margin: 0)
    
    # Coordinates come from the Job now: [x, y]
    signature_layer.image signature_image_path, at: coords, width: 120

    # 3. Merge the layers
    sig_pdf = CombinePDF.parse(signature_layer.render)
    
    # Adjust here if the signature should be on the first page or last page
    pdf.pages.last << sig_pdf.pages[0]

    # 4. Return the new PDF data
    pdf.to_pdf
  end
end