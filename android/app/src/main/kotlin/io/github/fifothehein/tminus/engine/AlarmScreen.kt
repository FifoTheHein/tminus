package io.github.fifothehein.tminus.engine

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import io.github.fifothehein.tminus.R
import kotlinx.coroutines.delay

data class AlarmCallbacks(
    val onJoin: (alertId: String) -> Unit,
    val onDismiss: (alertId: String) -> Unit,
    val onDismissAll: () -> Unit,
    val onSnooze: (SnoozeOption) -> Unit,
)

/**
 * Alarm-screen colours that have no design token. Sources: design-system.png "AlarmButton"
 * (2 px outline) with docs/design/1b-alarm-dark.png, and docs/design/6f-alarm-light.png.
 */
private object AlarmScreenColors {
    val DarkButtonOutline = Color(0xFF4A5A72)
    val LightButtonOutline = Color(0xFF8FA3BF)
    val LightButtonFill = Color(0x99FFFFFF) // rgba(255, 255, 255, 0.6)
    val LightText = Color(0xFF10141B)
}

@Immutable
private data class AlarmPalette(
    val dark: Boolean,
    val surface: Color,
    val text: Color,
    val textVariant: Color,
    val card: Color,
    val chipBg: Color,
    val chipFg: Color,
    val buttonOutline: Color,
    val buttonFill: Color,
    val buttonText: Color,
    val inverseSurface: Color,
    val onInverseSurface: Color,
    val onColorDark: Color,
    val onColorLight: Color,
    val calendarPairs: List<Pair<Int, Int>>,
) {
    fun eventColor(argb: Long): Color = Color(CalendarColors.forTheme(argb.toInt(), dark, calendarPairs))

    /** Text on a calendar-colour fill: dark on light colours, white on dark ones (design system JoinButton). */
    fun onColor(fill: Color): Color = if (fill.luminance() > 0.4f) onColorDark else onColorLight
}

@Composable
private fun alarmPalette(dark: Boolean): AlarmPalette {
    val pairs = listOf(
        colorResource(R.color.tminus_dark_calendarBlue).toArgb() to colorResource(R.color.tminus_light_calendarBlue).toArgb(),
        colorResource(R.color.tminus_dark_calendarGreen).toArgb() to colorResource(R.color.tminus_light_calendarGreen).toArgb(),
        colorResource(R.color.tminus_dark_calendarPurple).toArgb() to colorResource(R.color.tminus_light_calendarPurple).toArgb(),
        colorResource(R.color.tminus_dark_calendarOrange).toArgb() to colorResource(R.color.tminus_light_calendarOrange).toArgb(),
        colorResource(R.color.tminus_dark_calendarPink).toArgb() to colorResource(R.color.tminus_light_calendarPink).toArgb(),
        colorResource(R.color.tminus_dark_calendarTeal).toArgb() to colorResource(R.color.tminus_light_calendarTeal).toArgb(),
    )
    val onColorDark = colorResource(R.color.tminus_dark_onPrimary)
    val onColorLight = colorResource(R.color.tminus_light_onPrimary)
    return if (dark) {
        AlarmPalette(
            dark = true,
            surface = colorResource(R.color.tminus_dark_surface),
            text = colorResource(R.color.tminus_dark_onSurface),
            textVariant = colorResource(R.color.tminus_dark_onSurfaceVariant),
            card = colorResource(R.color.tminus_dark_surfaceContainerHigh),
            chipBg = colorResource(R.color.tminus_dark_alarmChipBg),
            chipFg = colorResource(R.color.tminus_dark_alarmChipFg),
            buttonOutline = AlarmScreenColors.DarkButtonOutline,
            buttonFill = Color.Transparent,
            buttonText = colorResource(R.color.tminus_dark_onSurface),
            inverseSurface = colorResource(R.color.tminus_dark_inverseSurface),
            onInverseSurface = colorResource(R.color.tminus_dark_onInverseSurface),
            onColorDark = onColorDark,
            onColorLight = onColorLight,
            calendarPairs = pairs,
        )
    } else {
        AlarmPalette(
            dark = false,
            surface = colorResource(R.color.tminus_light_surface),
            text = AlarmScreenColors.LightText,
            textVariant = colorResource(R.color.tminus_light_onSurfaceVariant),
            card = colorResource(R.color.tminus_light_surfaceContainer),
            chipBg = colorResource(R.color.tminus_light_alarmChipBg),
            chipFg = colorResource(R.color.tminus_light_alarmChipFg),
            buttonOutline = AlarmScreenColors.LightButtonOutline,
            buttonFill = AlarmScreenColors.LightButtonFill,
            buttonText = AlarmScreenColors.LightText,
            inverseSurface = colorResource(R.color.tminus_light_inverseSurface),
            onInverseSurface = colorResource(R.color.tminus_light_onInverseSurface),
            onColorDark = onColorDark,
            onColorLight = onColorLight,
            calendarPairs = pairs,
        )
    }
}

/** The design system's type scale for this screen (lib/app/theme/tminus_type.dart and tminus_text_theme.dart). */
private class AlarmType(fonts: AlarmFonts) {
    val countdown = TextStyle(fontFamily = fonts.mono, fontWeight = FontWeight.Medium, fontSize = 120.sp, lineHeight = 114.sp, letterSpacing = (-0.05).em)
    val countdownUnit = TextStyle(fontFamily = fonts.mono, fontWeight = FontWeight.Medium, fontSize = 40.sp, lineHeight = 40.sp)
    val nowWord = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.Medium, fontSize = 96.sp, lineHeight = 100.sp, letterSpacing = (-0.02).em)
    val prefix = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.Normal, fontSize = 20.sp, lineHeight = 26.sp)
    val title = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.Medium, fontSize = 32.sp, lineHeight = 37.sp, letterSpacing = (-0.01).em)
    val timeLarge = TextStyle(fontFamily = fonts.mono, fontWeight = FontWeight.Normal, fontSize = 18.sp, lineHeight = 24.sp)
    val body = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 24.sp)
    val cardTitle = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.Medium, fontSize = 20.sp, lineHeight = 26.sp)
    val cardMeta = TextStyle(fontFamily = fonts.mono, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp)
    val chip = TextStyle(fontFamily = fonts.mono, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 20.sp, letterSpacing = 0.05.em)
    val buttonLarge = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, lineHeight = 24.sp)
    val button = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp)
    val link = TextStyle(fontFamily = fonts.sans, fontWeight = FontWeight.Medium, fontSize = 16.sp, lineHeight = 20.sp, textDecoration = TextDecoration.Underline)
}

@Composable
fun AlarmScreen(alerts: List<PlannedAlert>, fonts: AlarmFonts, text: AlertText, callbacks: AlarmCallbacks) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            now = System.currentTimeMillis()
        }
    }
    var snoozeOpen by remember { mutableStateOf(false) }
    val palette = alarmPalette(isSystemInDarkTheme())
    val type = remember(fonts) { AlarmType(fonts) }
    val model = AlarmScreenModel.of(alerts, now, text) ?: return
    val wash = palette.eventColor(model.items.first().color)

    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    0f to wash.copy(alpha = 0.22f).compositeOver(palette.surface),
                    0.6f to palette.surface,
                    1f to palette.surface,
                ),
            ),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .systemBarsPadding()
                .padding(horizontal = 24.dp, vertical = 24.dp),
        ) {
            Chip(model.chip, palette, type)
            Spacer(Modifier.height(40.dp))
            Headline(model, palette, type)
            if (model.coalesced) {
                Spacer(Modifier.height(24.dp))
                CoalescedList(model.items, palette, type, callbacks, Modifier.weight(1f))
            } else {
                Spacer(Modifier.height(40.dp))
                EventBlock(model.items.single(), palette, type)
                Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.height(16.dp))
            if (snoozeOpen) {
                SnoozeChoices(model.snoozeOptions, palette, type) { option ->
                    snoozeOpen = false
                    callbacks.onSnooze(option)
                }
                Spacer(Modifier.height(12.dp))
            }
            if (model.coalesced) {
                CoalescedActions(palette, type, snoozeOpen, { snoozeOpen = !snoozeOpen }, callbacks.onDismissAll)
            } else {
                SingleActions(model.items.single(), palette, type, snoozeOpen, { snoozeOpen = !snoozeOpen }, callbacks)
            }
        }
    }
}

@Composable
private fun Chip(label: String, palette: AlarmPalette, type: AlarmType) {
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(palette.chipBg)
            .height(36.dp)
            .padding(start = 12.dp, end = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(R.drawable.ic_alarm, palette.chipFg, 20.dp)
        Spacer(Modifier.width(6.dp))
        BasicText(label, style = type.chip.copy(color = palette.chipFg))
    }
}

@Composable
private fun Headline(model: AlarmScreenModel, palette: AlarmPalette, type: AlarmType) {
    val h = model.headline
    Column {
        if (h.prefix != null) BasicText(h.prefix, style = type.prefix.copy(color = palette.textVariant))
        if (h.unit == null) {
            BasicText(h.number, style = type.nowWord.copy(color = palette.text))
        } else {
            Row(verticalAlignment = Alignment.Bottom) {
                BasicText(h.number, style = type.countdown.copy(color = palette.text))
                Spacer(Modifier.width(8.dp))
                BasicText(h.unit, style = type.countdownUnit.copy(color = palette.text), modifier = Modifier.padding(bottom = 14.dp))
            }
        }
        if (model.subtitle != null) {
            Spacer(Modifier.height(8.dp))
            BasicText(model.subtitle, style = type.prefix.copy(color = palette.textVariant))
        }
    }
}

@Composable
private fun EventBlock(item: AlarmScreenModel.Item, palette: AlarmPalette, type: AlarmType) {
    Row(Modifier.height(IntrinsicSize.Min)) {
        Box(
            Modifier
                .width(4.dp)
                .fillMaxHeight()
                .clip(RoundedCornerShape(2.dp))
                .background(palette.eventColor(item.color)),
        )
        Spacer(Modifier.width(16.dp))
        Column {
            BasicText(item.title, style = type.title.copy(color = palette.text))
            Spacer(Modifier.height(8.dp))
            BasicText(item.range, style = type.timeLarge.copy(color = palette.textVariant))
            if (item.where != null) {
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (item.joinUrl != null) {
                        Icon(R.drawable.ic_videocam, palette.textVariant, 20.dp)
                        Spacer(Modifier.width(10.dp))
                    }
                    BasicText(item.where, style = type.body.copy(color = palette.textVariant))
                }
            }
        }
    }
}

@Composable
private fun CoalescedList(
    items: List<AlarmScreenModel.Item>,
    palette: AlarmPalette,
    type: AlarmType,
    callbacks: AlarmCallbacks,
    modifier: Modifier,
) {
    Column(
        modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items.forEach { item -> EventCard(item, palette, type, callbacks) }
    }
}

@Composable
private fun EventCard(item: AlarmScreenModel.Item, palette: AlarmPalette, type: AlarmType, callbacks: AlarmCallbacks) {
    val color = palette.eventColor(item.color)
    Row(
        Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(20.dp))
            .background(palette.card),
    ) {
        Box(
            Modifier
                .width(4.dp)
                .fillMaxHeight()
                .background(color),
        )
        Column(Modifier.padding(start = 20.dp, end = 16.dp, top = 16.dp, bottom = 16.dp)) {
            BasicText(item.title, style = type.cardTitle.copy(color = palette.text))
            Spacer(Modifier.height(4.dp))
            BasicText(listOfNotNull(item.range, item.where).joinToString(" · "), style = type.cardMeta.copy(color = palette.textVariant))
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (item.joinUrl != null) {
                    AlarmButton("Join", { callbacks.onJoin(item.alertId) }, Modifier.weight(1f), 64.dp, color, palette.onColor(color), null, R.drawable.ic_videocam, type.button)
                }
                AlarmButton("Dismiss", { callbacks.onDismiss(item.alertId) }, Modifier.weight(1f), 64.dp, palette.buttonFill, palette.buttonText, palette.buttonOutline, null, type.button)
            }
        }
    }
}

@Composable
private fun SnoozeChoices(options: List<SnoozeOption>, palette: AlarmPalette, type: AlarmType, onPick: (SnoozeOption) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        options.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { option ->
                    AlarmButton(option.label, { onPick(option) }, Modifier.weight(1f), 64.dp, palette.buttonFill, palette.buttonText, palette.buttonOutline, null, type.button)
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun SingleActions(
    item: AlarmScreenModel.Item,
    palette: AlarmPalette,
    type: AlarmType,
    snoozeOpen: Boolean,
    onToggleSnooze: () -> Unit,
    callbacks: AlarmCallbacks,
) {
    val fill = palette.eventColor(item.color)
    val snoozeLabel = if (snoozeOpen) "Cancel" else "Snooze"
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (item.joinUrl != null) {
            AlarmButton("Join", { callbacks.onJoin(item.alertId) }, Modifier.fillMaxWidth(), 76.dp, fill, palette.onColor(fill), null, R.drawable.ic_videocam, type.buttonLarge)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AlarmButton(snoozeLabel, onToggleSnooze, Modifier.weight(1f), 64.dp, palette.buttonFill, palette.buttonText, palette.buttonOutline, R.drawable.ic_snooze, type.button)
                AlarmButton("Dismiss", { callbacks.onDismiss(item.alertId) }, Modifier.weight(1f), 64.dp, palette.buttonFill, palette.buttonText, palette.buttonOutline, null, type.button)
            }
        } else {
            AlarmButton("Dismiss", { callbacks.onDismiss(item.alertId) }, Modifier.fillMaxWidth(), 76.dp, fill, palette.onColor(fill), null, null, type.buttonLarge)
            AlarmButton(snoozeLabel, onToggleSnooze, Modifier.fillMaxWidth(), 64.dp, palette.buttonFill, palette.buttonText, palette.buttonOutline, R.drawable.ic_snooze, type.button)
        }
        LinkButton("Dismiss all alerts for this event", callbacks.onDismissAll, palette, type)
    }
}

@Composable
private fun CoalescedActions(palette: AlarmPalette, type: AlarmType, snoozeOpen: Boolean, onToggleSnooze: () -> Unit, onDismissAll: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        AlarmButton(if (snoozeOpen) "Cancel" else "Snooze all", onToggleSnooze, Modifier.weight(1f), 64.dp, palette.buttonFill, palette.buttonText, palette.buttonOutline, R.drawable.ic_snooze, type.button)
        AlarmButton("Dismiss all", onDismissAll, Modifier.weight(1f), 64.dp, palette.inverseSurface, palette.onInverseSurface, null, null, type.button)
    }
}

/** A pill button; no swipe gestures anywhere on this screen (brief §9). */
@Composable
private fun AlarmButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier,
    height: Dp,
    fill: Color,
    content: Color,
    outline: Color?,
    icon: Int?,
    style: TextStyle,
) {
    val shape = RoundedCornerShape(50)
    Row(
        modifier = modifier
            .height(height)
            .clip(shape)
            .background(fill)
            .then(if (outline != null) Modifier.border(2.dp, outline, shape) else Modifier)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, content, 24.dp)
            Spacer(Modifier.width(10.dp))
        }
        BasicText(label, style = style.copy(color = content, textAlign = TextAlign.Center), maxLines = 2)
    }
}

@Composable
private fun LinkButton(label: String, onClick: () -> Unit, palette: AlarmPalette, type: AlarmType) {
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(label, style = type.link.copy(color = palette.text))
    }
}

@Composable
private fun Icon(id: Int, tint: Color, size: Dp) {
    Image(painterResource(id), contentDescription = null, modifier = Modifier.size(size), colorFilter = ColorFilter.tint(tint))
}
