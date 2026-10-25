/// Interface language. English text is the key; other languages map it.
String appLang = 'en';

const languages = {'en': 'English', 'ru': 'Русский'};

/// Translates [en] into the current language, filling `{name}` placeholders.
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = appLang == 'ru' ? (_ru[en] ?? _en[en] ?? en) : (_en[en] ?? en);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Russian plural form for counts: one (1, 21), few (2-4, 22-24), many.
String plural(int n, String one, String few, String many) {
  if (appLang != 'ru') return n == 1 ? one : many;
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

/// English forms for plural keys that only exist to pick the right Russian form.
const _en = <String, String>{'boxes2': 'boxes', 'openings2': 'openings', 'areas2': 'areas', 'rooms2': 'rooms'};

const _ru = <String, String>{
  'box': 'коробка',
  'boxes2': 'коробки',
  'boxes': 'коробок',
  'opening': 'проём',
  'openings2': 'проёма',
  'openings': 'проёмов',
  'area': 'участок',
  'areas2': 'участка',
  'areas': 'участков',
  'm²': 'м²',
  // Home
  'Kafelito': 'Kafelito',
  'Rooms': 'Комнаты',
  'Tiles': 'Плитка',
  'New room': 'Новая комната',
  'New tile': 'Новая плитка',
  'Name': 'Название',
  'Create': 'Создать',
  'Cancel': 'Отмена',
  'Save': 'Сохранить',
  'Delete': 'Удалить',
  'Remove': 'Убрать',
  'Duplicate': 'Дублировать',
  'Room {n}': 'Комната {n}',
  'Room': 'Комната',
  '{name} copy': '{name} (копия)',
  'Delete {name}?': 'Удалить «{name}»?',
  'This cannot be undone.': 'Это действие нельзя отменить.',
  'No rooms yet. Tap New room to draw one.': 'Комнат пока нет. Нажмите «Новая комната», чтобы начертить.',
  'No tiles yet. Tap + to photograph one.': 'Плитки пока нет. Нажмите «Новая плитка», чтобы сфотографировать.',
  'Plan not finished': 'План не завершён',
  '{n} walls · {area} m² floor': 'Стен: {n} · пол {area} м²',
  'Floor {f} · walls {w} {m2}': 'Пол {f} · стены {w} {m2}',
  'Total {t} {m2} · tiled {a} {m2}': 'Всего {t} {m2} · под плитку {a} {m2}',
  'Settings': 'Настройки',
  'Language': 'Язык',
  'Default tile gap for new rooms': 'Шов между плиткой для новых комнат',
  'Apply to all rooms': 'Применить ко всем комнатам',
  'Tile gap set to {gap} mm in all rooms.': 'Шов {gap} мм установлен во всех комнатах.',
  'mm': 'мм',
  'cm': 'см',

  // Tile editor
  'Edit tile': 'Изменить плитку',
  'Delete tile?': 'Удалить плитку?',
  'Used in {n}': 'Используется: {n}',
  'Remove it from these rooms to change or delete it, or change a copy instead.':
      'Чтобы изменить или удалить плитку, уберите её из этих комнат или измените копию.',
  'Remove {tile} from {room}?': 'Убрать «{tile}» из «{room}»?',
  'Walls and floor with this tile become untiled and its drawn areas are deleted.':
      'Стены и пол с этой плиткой останутся без плитки, а её участки будут удалены.',
  'Copy and edit': 'Копировать и изменить',
  'Edit': 'Изменить',
  'Not used in any room now.': 'Сейчас не используется ни в одной комнате.',
  'room': 'комната',
  'rooms2': 'комнаты',
  'rooms': 'комнат',
  'It will be removed from every room that uses it.': 'Она будет убрана из всех комнат, где используется.',
  'Take photo': 'Сфотографировать',
  'Gallery': 'Галерея',
  'Remove photo': 'Убрать фото',
  'Width': 'Ширина',
  'Height': 'Высота',
  'Depth': 'Глубина',
  'Item code': 'Артикул',
  'Pieces per box (optional)': 'Штук в коробке (необязательно)',
  'Colour (used when there is no photo)': 'Цвет (если нет фото)',
  'Save tile': 'Сохранить плитку',
  'Enter the tile width and height': 'Укажите ширину и высоту плитки',
  'Could not get photo: {e}': 'Не удалось получить фото: {e}',
  'Frame one tile': 'Выделите одну плитку',
  'Use': 'Готово',
  'Unlock shape': 'Свободная форма',
  'Lock to tile size': 'По размеру плитки',
  'Drag the corners so the box covers exactly one tile.': 'Перетащите углы, чтобы рамка охватывала ровно одну плитку.',
  'Tile': 'Плитка',
  'No tiles': 'Без плитки',

  // Project
  'Undo': 'Отменить',
  'Room settings': 'Настройки комнаты',
  'Tile gap': 'Шов между плиткой',
  'Extra for waste': 'Запас на подрезку',
  'Top view': 'План',
  '3D': '3D',
  'Measurements': 'Расчёт',
  'Tap to place the corners of the room.': 'Нажимайте, чтобы поставить углы комнаты.',
  'Tap the first corner (or Close) to finish the room.':
      'Нажмите на первый угол (или «Замкнуть»), чтобы завершить комнату.',
  'Double-tap a corner, wall, floor or fixture to edit. Long-press a wall to add a corner.':
      'Двойное нажатие на угол, стену, пол или сантехнику — изменить. Долгое нажатие на стену — добавить угол.',
  'Remove point': 'Убрать точку',
  'Close room': 'Замкнуть',
  'Add fixture': 'Мебель и техника',
  'Floor': 'Пол',
  'Reopen plan': 'Изменить план',
  'Fit to screen': 'По размеру экрана',
  'Corner added. Drag it into place.': 'Угол добавлен. Перетащите его на место.',
  'Remove corner?': 'Убрать угол?',
  'The two walls next to it become one.': 'Две соседние стены станут одной.',

  // Dialogs
  'Corner angle': 'Угол',
  'Angle': 'Угол',
  'Set': 'Применить',
  'Now {a}°. The opposite wall stretches to fit.': 'Сейчас {a}°. Противоположная стена подстроится.',
  'Wall {n}': 'Стена {n}',
  'W{n}': 'С{n}',
  'Length': 'Длина',
  'Wall tile': 'Плитка стены',
  'Open wall view': 'Открыть стену',
  'Open wall view ({areas}, {openings})': 'Открыть стену ({areas}, {openings})',
  'Floor tile': 'Плитка пола',
  'Changing these stretches the whole room.': 'Изменение растянет всю комнату.',
  'Draw tiled areas on the floor': 'Нарисовать участки на полу',
  'From floor': 'От пола',
  'Rotation': 'Поворот',
  'Door / window': 'Дверь / окно',
  'Door': 'Дверь',
  'Window': 'Окно',
  'From wall start': 'От начала стены',
  'Tiles for this area': 'Плитка для участка',
  'Delete area': 'Удалить участок',
  'Tile direction': 'Направление плитки',
  '{full} whole + {cut} cut, {p}% extra · {area} m²': '{full} целых + {cut} подрезанных, запас {p}% · {area} м²',

  // Fixtures
  'Sink': 'Раковина',
  'Toilet': 'Унитаз',
  'Shower': 'Душ',
  'Bathtub': 'Ванна',
  'Washing machine': 'Стиральная машина',
  'Cabinet': 'Шкафчик',
  'Mirror': 'Зеркало',
  'Fridge': 'Холодильник',
  'Stove with oven': 'Плита с духовкой',
  'Dishwasher': 'Посудомоечная машина',
  'Kitchen counter': 'Кухонная тумба',
  'Table': 'Стол',
  'Chair': 'Стул',
  'Sofa': 'Диван',
  'Bed': 'Кровать',
  'Wardrobe': 'Шкаф',
  'From left corner': 'От левого угла',

  // Wall / floor editor
  'Previous wall': 'Предыдущая стена',
  'Next wall': 'Следующая стена',
  'Whole surface tile': 'Плитка на всю поверхность',
  'Tiles for the whole wall': 'Плитка на всю стену',
  'Tiles for the whole floor': 'Плитка на весь пол',
  'Tap to place the corners of the area.': 'Нажимайте, чтобы поставить углы участка.',
  'Tap the first corner to finish the area.': 'Нажмите на первый угол, чтобы завершить участок.',
  'Drag to draw a rectangle.': 'Проведите пальцем, чтобы нарисовать прямоугольник.',
  'Double-tap an area, door or the wall to edit it. Drag to move.':
      'Двойное нажатие на участок, дверь или стену — изменить. Перетаскивание — переместить.',
  'Select': 'Выбор',
  'Rectangle': 'Прямоугольник',
  'Shape': 'Фигура',
  'Undo point': 'Убрать точку',
  'Fixture': 'Мебель',

  // 3D
  'Finish the room plan to see it in 3D.': 'Завершите план комнаты, чтобы увидеть 3D.',
  'Inside': 'Внутри',
  'Overview': 'Обзор',
  'Drag to look around · pinch to walk': 'Проведите — осмотреться · щипок — идти',
  'Drag to orbit · pinch to zoom': 'Проведите — вращать · щипок — масштаб',

  // Measurements
  'Finish the room plan to see measurements.': 'Завершите план комнаты, чтобы увидеть расчёт.',
  'Walls': 'Стены',
  'Tiles to buy': 'Сколько купить',
  'No tiles assigned yet. Double-tap a wall or the floor in the plan to choose tiles.':
      'Плитка ещё не выбрана. Дважды нажмите на стену или пол на плане.',
  'Area covered': 'Площадь',
  'Whole tiles': 'Целые плитки',
  'Cut tiles': 'Подрезанные плитки',
  'With {p}% extra': 'С запасом {p}%',
  '{n} pcs': '{n} шт.',
  'A tile that is only partly inside an area counts as one cut tile. Offcuts are not reused, so real needs may be a little lower.': 'Плитка, которая лишь частично попадает в участок, считается одной подрезанной. Обрезки повторно не используются, поэтому реально может понадобиться немного меньше.',
  // Layout start, collections, try-out, export
  'Start tiling': 'Начало раскладки',
  'Whole tile in the top left corner, then right and down': 'Целая плитка в левом верхнем углу, далее вправо и вниз',
  'Whole tile in the left corner on the floor, then right and up':
      'Целая плитка в левом углу у пола, далее вправо и вверх',
  'Whole tile in the top right corner, then left and down': 'Целая плитка в правом верхнем углу, далее влево и вниз',
  'Whole tile in the right corner on the floor, then left and up':
      'Целая плитка в правом углу у пола, далее влево и вверх',
  'Equal cut pieces on opposite sides, whole tiles between':
      'Одинаковая подрезка с противоположных сторон, целые плитки между ними',
  'Equal cut pieces at both ends, whole tiles from the floor': 'Одинаковая подрезка по краям, целые плитки от пола',
  'Collections': 'Коллекции',
  'New collection': 'Новая коллекция',
  'Collection': 'Коллекция',
  'Group a wall, floor and decor tile to lay a whole room at once.':
      'Объедините плитку для стен, пола и декор, чтобы разложить всю комнату сразу.',
  'Decor tile': 'Декор',
  'Decor band from floor': 'Полоса декора от пола',
  'Tile collection': 'Коллекция плитки',
  'Laid automatically when you close the plan.': 'Разложится автоматически, когда план будет замкнут.',
  'Choosing one lays it on the walls and floor.': 'При выборе раскладывается на стены и пол.',
  'None': 'Нет',
  'Try other tiles': 'Примерить плитку',
  'Changes are only a try-out until you keep them. Revert brings back the saved tiles.':
      'Это примерка, пока вы её не сохраните. «Вернуть» восстановит прежнюю плитку.',
  'Lay a collection': 'Разложить коллекцию',
  'Tiles in this room': 'Плитка в этой комнате',
  'No tiles assigned yet.': 'Плитка ещё не выбрана.',
  'Replace {tile}': 'Заменить «{tile}»',
  'See in 3D': 'Смотреть в 3D',
  'Keep the tiles you tried?': 'Оставить примеренную плитку?',
  'Revert brings back the tiles saved before the try-out.': '«Вернуть» восстановит плитку, которая была до примерки.',
  'Stay': 'Остаться',
  'Revert': 'Вернуть',
  'Keep': 'Оставить',
  'Trying tiles. Not kept yet.': 'Примерка плитки, ещё не сохранена.',
  'Swap': 'Заменить',
  'Export for customer': 'Экспорт для заказчика',
  'from the left': 'слева',
  'from the right': 'справа',
  'centred': 'по центру',
  'inside view': 'вид изнутри',
  'laid': 'укладка',
  'gap': 'шов',
  '{full} whole + {cut} cut': '{full} целых + {cut} подрезанных',
  'Cut tile: number, then the piece size width × height in cm as seen in this view':
      'Подрезанная плитка: номер и размер куска ширина × высота в см, как на этом виде',
  'Preparing…': 'Подготовка…',
  'Sharing…': 'Отправка…',
  'Export failed: {e}': 'Не удалось экспортировать: {e}',
  'JPG pictures named date-tile-details, for example {e}': 'Картинки JPG с именем дата-плитка-детали, например {e}',
  'Tile layouts': 'Схемы раскладки',
  'Joint lines, tile numbers and cut sizes for every wall and the floor':
      'Швы, номера плиток и размеры подрезки для каждой стены и пола',
  'Clean views': 'Чистые виды',
  'Only the tiles, no extra information': 'Только плитка, без лишней информации',
  '3D pictures': '3D-картинки',
  'Views from inside the room and from above': 'Виды изнутри комнаты и сверху',
  'Create and share': 'Создать и отправить',
};
