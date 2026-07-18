export default function FoodDetailModal({ food, onClose, onAddToCart }) {
  if (!food) return null

  const formattedPrice = new Intl.NumberFormat('vi-VN', {
    style: 'currency',
    currency: 'VND',
  }).format(food.price)

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-lg max-w-md w-full overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="aspect-video bg-gray-100">
          {food.image ? (
            <img src={food.image} alt={food.name} className="w-full h-full object-cover" />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-gray-400">
              Chưa có ảnh
            </div>
          )}
        </div>

        <div className="p-5">
          <div className="flex items-start justify-between">
            <h2 className="text-xl font-bold">{food.name}</h2>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">
              ✕
            </button>
          </div>

          <p className="text-gray-600 mt-2">{food.description || 'Chưa có mô tả cho món này.'}</p>

          <div className="flex items-center justify-between mt-4">
            <span className="text-xl font-bold text-orange-500">{formattedPrice}</span>

            {food.available ? (
              <button
                onClick={() => {
                  onAddToCart(food)
                  onClose()
                }}
                className="bg-orange-500 text-white px-4 py-2 rounded hover:bg-orange-600"
              >
                Thêm vào giỏ
              </button>
            ) : (
              <span className="text-sm text-gray-400 italic">Hết món</span>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}