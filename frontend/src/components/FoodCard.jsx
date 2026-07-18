export default function FoodCard({ food, onAddToCart, onViewDetail }) {
  const formattedPrice = new Intl.NumberFormat('vi-VN', {
    style: 'currency',
    currency: 'VND',
  }).format(food.price)

  return (
    <div
      className="bg-white rounded-lg shadow p-4 flex gap-4 cursor-pointer hover:shadow-md transition"
      onClick={() => onViewDetail(food)}
    >
      <div className="w-24 h-24 flex-shrink-0 bg-gray-100 rounded overflow-hidden">
        {food.image ? (
          <img src={food.image} alt={food.name} className="w-full h-full object-cover" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-gray-400 text-xs">
            Chưa có ảnh
          </div>
        )}
      </div>

      <div className="flex-1 flex flex-col justify-between">
        <div>
          <h3 className="font-semibold">{food.name}</h3>
          <p className="text-gray-500 text-sm line-clamp-2">{food.description}</p>
        </div>

        <div className="flex items-center justify-between mt-2">
          <span className="font-bold text-orange-500">{formattedPrice}</span>

          {food.available ? (
            <button
              onClick={(e) => {
                e.stopPropagation() // Ngăn không cho click nút "Thêm" cũng kích hoạt mở modal
                onAddToCart(food)
              }}
              className="bg-orange-500 text-white text-sm px-3 py-1.5 rounded hover:bg-orange-600"
            >
              Thêm
            </button>
          ) : (
            <span className="text-xs text-gray-400 italic">Hết món</span>
          )}
        </div>
      </div>
    </div>
  )
}